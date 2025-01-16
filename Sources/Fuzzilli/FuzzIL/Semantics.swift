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


// Miscellaneous semantics of FuzzIL. Also see JSTyper for execution semantics of operations.

extension Operation {
    /// Returns true if this operation could mutate its ith input.
    func mayMutate(input inputIdx: Int) -> Bool {
        if reassigns(input: inputIdx) {
            return true
        }

        switch opcode {
        case .callFunction,
             .callMethod,
             .callComputedMethod:
             // We assume that a constructor doesn't modify its arguments when called.
            return true
        case .setProperty,
             .updateProperty,
             .setElement,
             .updateElement,
             .setComputedProperty,
             .updateComputedProperty,
             .yield,
             .deleteProperty,
             .deleteComputedProperty,
             .deleteElement:
            return inputIdx == 0
        default:
            return false
        }
    }

    func reassigns(input inputIdx: Int) -> Bool {
        switch opcode {
        case .reassign,
             .update:
            return inputIdx == 0
        case .unaryOperation(let op):
            return op.op.reassignsInput
        case .destructArrayAndReassign,
             .destructObjectAndReassign:
            return inputIdx != 0
        default:
            return false
        }
    }
}

extension Instruction {
    /// Returns true if this operation could mutate the given input variable when executed.
    func mayMutate(_ v: Variable) -> Bool {
        for (idx, input) in inputs.enumerated() {
            if input == v {
                if op.mayMutate(input: idx) {
                    return true
                }
            }
        }
        return false
    }

    /// Returns true if this operation could mutate any of the given input variables when executed.
    func mayMutate(anyOf vars: VariableSet) -> Bool {
        for (idx, input) in inputs.enumerated() {
            if vars.contains(input) {
                if op.mayMutate(input: idx) {
                    return true
                }
            }
        }
        return false
    }

    /// Returns true if this operation reassigns the given variable.
    func reassigns(_ v: Variable) -> Bool {
        for (idx, input) in inputs.enumerated() {
            if input == v {
                if op.reassigns(input: idx) {
                    return true
                }
            }
        }
        return false
    }

    /// Returns true if the this and the given instruction can be folded into one.
    /// This is generally possible if they are identical and pure, i.e. don't have side-effects.
    func canFold(_ other: Instruction) -> Bool {
        var canFold = false
        switch (self.op.opcode, other.op.opcode) {
        case (.loadInteger(let op1), .loadInteger(let op2)):
            canFold = op1.value == op2.value
        case (.loadBigInt(let op1), .loadBigInt(let op2)):
            canFold = op1.value == op2.value
        case (.loadFloat(let op1), .loadFloat(let op2)):
            canFold = op1.value == op2.value
        case (.loadString(let op1), .loadString(let op2)):
            canFold = op1.value == op2.value
        case (.loadBoolean(let op1), .loadBoolean(let op2)):
            canFold = op1.value == op2.value
        case (.loadUndefined, .loadUndefined):
            canFold = true
        case (.loadNull, .loadNull):
            canFold = true
        case (.loadRegExp(let op1), .loadRegExp(let op2)):
            canFold = op1.pattern  == op2.pattern && op1.flags == op2.flags
        default:
            assert(self.op.name != other.op.name)
        }

        return canFold
    }
}

extension Operation {
    func isMatchingEnd(for beginOp: Operation) -> Bool {
        let endOp = self
        switch beginOp.opcode {
        case .beginObjectLiteral:
            return endOp is EndObjectLiteral
        case .beginObjectLiteralMethod:
            return endOp is EndObjectLiteralMethod
        case .beginObjectLiteralComputedMethod:
            return endOp is EndObjectLiteralComputedMethod
        case .beginObjectLiteralGetter:
            return endOp is EndObjectLiteralGetter
        case .beginObjectLiteralSetter:
            return endOp is EndObjectLiteralSetter
        case .beginClassDefinition:
             return endOp is EndClassDefinition
        case .beginClassConstructor:
            return endOp is EndClassConstructor
        case .beginClassInstanceMethod:
            return endOp is EndClassInstanceMethod
        case .beginClassInstanceGetter:
            return endOp is EndClassInstanceGetter
        case .beginClassInstanceSetter:
            return endOp is EndClassInstanceSetter
        case .beginClassStaticInitializer:
            return endOp is EndClassStaticInitializer
        case .beginClassStaticMethod:
            return endOp is EndClassStaticMethod
        case .beginClassStaticGetter:
            return endOp is EndClassStaticGetter
        case .beginClassStaticSetter:
            return endOp is EndClassStaticSetter
        case .beginClassPrivateInstanceMethod:
            return endOp is EndClassPrivateInstanceMethod
        case .beginClassPrivateStaticMethod:
            return endOp is EndClassPrivateStaticMethod
        case .beginPlainFunction:
            return endOp is EndPlainFunction
        case .beginArrowFunction:
            return endOp is EndArrowFunction
        case .beginGeneratorFunction:
            return endOp is EndGeneratorFunction
        case .beginAsyncFunction:
            return endOp is EndAsyncFunction
        case .beginAsyncArrowFunction:
            return endOp is EndAsyncArrowFunction
        case .beginAsyncGeneratorFunction:
            return endOp is EndAsyncGeneratorFunction
        case .beginConstructor:
            return endOp is EndConstructor
        case .beginWith:
            return endOp is EndWith
        case .beginIf:
            return endOp is BeginElse || endOp is EndIf
        case .beginElse:
            return endOp is EndIf
        case .beginSwitch:
            return endOp is EndSwitch
        case .beginSwitchCase,
             .beginSwitchDefaultCase:
            return endOp is EndSwitchCase
        case .beginWhileLoopHeader:
            return endOp is BeginWhileLoopBody
        case .beginWhileLoopBody:
            return endOp is EndWhileLoop
        case .beginDoWhileLoopBody:
            return endOp is BeginDoWhileLoopHeader
        case .beginDoWhileLoopHeader:
            return endOp is EndDoWhileLoop
        case .beginForLoopInitializer:
            return endOp is BeginForLoopCondition
        case .beginForLoopCondition:
            return endOp is BeginForLoopAfterthought
        case .beginForLoopAfterthought:
            return endOp is BeginForLoopBody
        case .beginForLoopBody:
            return endOp is EndForLoop
        case .beginForInLoop:
            return endOp is EndForInLoop
        case .beginForOfLoop,
             .beginForOfLoopWithDestruct:
            return endOp is EndForOfLoop
        case .beginRepeatLoop:
            return endOp is EndRepeatLoop
        case .beginTry:
            return endOp is BeginCatch || endOp is BeginFinally
        case .beginCatch:
            return endOp is BeginFinally || endOp is EndTryCatchFinally
        case .beginFinally:
            return endOp is EndTryCatchFinally
        case .beginCodeString:
            return endOp is EndCodeString
        case .beginBlockStatement:
            return endOp is EndBlockStatement
        case .beginWasmModule:
            return endOp is EndWasmModule
        case .beginWasmFunction:
            return endOp is EndWasmFunction
        case .wasmBeginBlock:
            return endOp is WasmEndBlock
        case .wasmBeginLoop:
            return endOp is WasmEndLoop
        case .wasmBeginTry,
             .wasmBeginCatch:
            return endOp is WasmEndTry || endOp is WasmBeginCatch || endOp is WasmBeginCatchAll
        case .wasmBeginCatchAll:
            return endOp is WasmEndTry
        case .wasmBeginTryDelegate:
            return endOp is WasmEndTryDelegate
        case .wasmBeginIf:
            return endOp is WasmEndIf || endOp is WasmBeginElse
        case .wasmBeginElse:
            return endOp is WasmEndIf
        default:
            fatalError("Unknown block operation \(beginOp)")
        }
    }

    func isMatchingStart(for endOp: Operation) -> Bool {
        return endOp.isMatchingEnd(for: self)
    }
}
