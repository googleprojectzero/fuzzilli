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

// Determine what variable types we should collect given instruction
struct TypeCollectionAnalyzer {
    // Special properties which significantly change variable type
    // We should recollect type if we change them
    let specialProperties = ["__proto__"]

    func analyze(_ instr: Instruction) -> [Variable] {
        switch instr.op {
            case is LoadInteger, is LoadBigInt, is LoadFloat, is LoadBoolean, is LoadNull, is LoadUndefined, is LoadVoid,
                 is TypeOf, is InstanceOf, is In, is Dup, is Reassign, is BinaryOperationAndReassign, is Compare, is BeginForIn:
                // No need to collect types for instructions interpreter can handle
                return []
            case is BeginAnyFunctionDefinition:
                // No type collection on function definitions for now
                return []
            case let op as StoreProperty where specialProperties.contains(op.propertyName):
                // Recollect type of this variable, because major change happened
                return [instr.input(0)]
            default:
                // By default, collect types for all outputs of an instruction
                return Array(instr.allOutputs)
        }
    }
}
