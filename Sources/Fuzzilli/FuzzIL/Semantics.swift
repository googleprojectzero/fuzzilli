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

        switch self {
        case is CallFunction,
             is CallMethod,
             is CallComputedMethod:
             // We assume that a constructor doesn't modify its arguments when called.
            return true
        case is StoreProperty,
             is StoreElement,
             is StoreComputedProperty,
             is Yield,
             is DeleteProperty,
             is DeleteComputedProperty,
             is DeleteElement:
            return inputIdx == 0
        case is BeginWhileLoop,
             is BeginDoWhileLoop:
            // We assume that loops mutate their run value (but, somewhat arbitrarily, not the value that it is compared against).
            return inputIdx == 0
        default:
            return false
        }
    }

    func reassigns(input inputIdx: Int) -> Bool {
        switch self {
        case is Reassign,
             is ReassignWithBinop:
            return inputIdx == 0
        case let op as UnaryOperation:
            return op.op.reassignsInput
        case is DestructArrayAndReassign,
             is DestructObjectAndReassign:
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
        switch (self.op, other.op) {
        case (let op1 as LoadInteger, let op2 as LoadInteger):
            canFold = op1.value == op2.value
        case (let op1 as LoadBigInt, let op2 as LoadBigInt):
            canFold = op1.value == op2.value
        case (let op1 as LoadFloat, let op2 as LoadFloat):
            canFold = op1.value == op2.value
        case (let op1 as LoadString, let op2 as LoadString):
            canFold = op1.value == op2.value
        case (let op1 as LoadBoolean, let op2 as LoadBoolean):
            canFold = op1.value == op2.value
        case (is LoadUndefined, is LoadUndefined):
            canFold = true
        case (is LoadNull, is LoadNull):
            canFold = true
        case (is LoadThis, is LoadThis):
            canFold = false
        case (is LoadArguments, is LoadArguments):
            canFold = false
        case (let op1 as LoadRegExp, let op2 as LoadRegExp):
            canFold = op1.value  == op2.value && op1.flags == op2.flags
        case (let op1 as LoadBuiltin, let op2 as LoadBuiltin):
            canFold = op1.builtinName  == op2.builtinName
        default:
            assert(self.op.name != other.op.name || !isPure)
        }

        assert(!canFold || isPure)
        return canFold
    }
}

extension Operation {
    func isMatchingEnd(for beginOp: Operation) -> Bool {
        let endOp = self
        switch beginOp {
        case is BeginPlainFunction:
            return endOp is EndPlainFunction
        case is BeginArrowFunction:
            return endOp is EndArrowFunction
        case is BeginGeneratorFunction:
            return endOp is EndGeneratorFunction
        case is BeginAsyncFunction:
            return endOp is EndAsyncFunction
        case is BeginAsyncArrowFunction:
            return endOp is EndAsyncArrowFunction
        case is BeginAsyncGeneratorFunction:
            return endOp is EndAsyncGeneratorFunction
        case is BeginConstructor:
            return endOp is EndConstructor
        case is BeginClass,
             is BeginMethod:
            return endOp is BeginMethod || endOp is EndClass
        case is BeginWith:
            return endOp is EndWith
        case is BeginIf:
            return endOp is BeginElse || endOp is EndIf
        case is BeginElse:
            return endOp is EndIf
        case is BeginSwitch:
            return endOp is EndSwitch
        case is BeginSwitchCase,
             is BeginSwitchDefaultCase:
            return endOp is EndSwitchCase
        case is BeginWhileLoop:
            return endOp is EndWhileLoop
        case is BeginDoWhileLoop:
            return endOp is EndDoWhileLoop
        case is BeginForLoop:
            return endOp is EndForLoop
        case is BeginForInLoop:
            return endOp is EndForInLoop
        case is BeginForOfLoop,
            is BeginForOfWithDestructLoop:
            return endOp is EndForOfLoop
        case is BeginTry:
            return endOp is BeginCatch || endOp is BeginFinally
        case is BeginCatch:
            return endOp is BeginFinally || endOp is EndTryCatchFinally
        case is BeginFinally:
            return endOp is EndTryCatchFinally
        case is BeginCodeString:
            return endOp is EndCodeString
        case is BeginBlockStatement:
            return endOp is EndBlockStatement
        default:
            fatalError("Unknown block operation \(beginOp)")
        }
    }
}
