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

/// Inlines functions at their callsite if possible to prevent deep nesting of functions.
struct InliningReducer: Reducer {
    var remaining = [Variable]()
    private let fuzzer: Fuzzer
    
    init(_ fuzzer: Fuzzer) {
        self.fuzzer = fuzzer
    }
    
    func reduce(_ program: Program, with verifier: ReductionVerifier) -> Program {
        var functions = [Variable]()
        var candidates = VariableMap<Int>()
        var stack = [Variable]()
        for instr in program {
            switch instr.operation {
            case is BeginFunctionDefinition:
                functions.append(instr.output)
                candidates[instr.output] = 0
                stack.append(instr.output)
            case is EndFunctionDefinition:
                stack.removeLast()
            case is CallFunction:
                let f = instr.input(0)
                
                // Can't inline recursive calls
                if stack.contains(f) {
                    candidates.remove(f)
                }
                
                if let callCount = candidates[f] {
                    candidates[f] = callCount + 1
                }

                for v in instr.inputs.dropFirst() {
                    candidates.remove(v)
                }
            default:
                for v in instr.inputs {
                    candidates.remove(v)
                }
            }
        }
        
        var current = program
        for f in functions {
            if candidates.contains(f) && candidates[f] == 1 {
                // Try inlining the function
                let newProgram = inline(f, in: current)
                if verifier.test(newProgram) {
                    current = newProgram
                }
            }
        }
        
        return current
    }
    
    func inline(_ function: Variable, in program: Program) -> Program {
        let b = fuzzer.makeBuilder()
        
        var i = 0
        
        while i < program.size {
            let instr = program[i]
            
            if instr.numOutputs > 0 && instr.output == function {
                assert(instr.operation is BeginFunctionDefinition)
                break
            }
            
            b.append(instr)
            
            i += 1
        }
        
        let funcDefinition = program[i]
        let parameters = Array(funcDefinition.innerOutputs)
        
        i += 1
        
        // Fast-forward to end of function definition
        var functionBody = [Instruction]()
        var depth = 0
        while i < program.size {
            let instr = program[i]
            
            if instr.operation is BeginFunctionDefinition {
                depth += 1
            }
            if instr.operation is EndFunctionDefinition {
                if depth == 0 {
                    i += 1
                    break
                } else {
                    depth -= 1
                }
            }
            
            functionBody.append(instr)
            
            i += 1
        }
        
        assert(i < program.size)
        
        // Search for the call of the function
        while i < program.size {
            let instr = program[i]
            
            if instr.operation is CallFunction && instr.input(0) == function {
                break
            }
            
            assert(!instr.inputs.contains(function))
            
            b.append(instr)
            i += 1
        }
        
        // Found it. Inline the function now
        let call = program[i]
        
        // Reuse the function variable to store 'undefined' and use that as
        // initial value of the return variable and for missing arguments.
        let undefined = funcDefinition.output
        b.append(Instruction(operation: LoadUndefined(), output: undefined))
        
        var arguments = VariableMap<Variable>()
        for (i, v) in parameters.enumerated() {
            if call.numInputs - 1 > i {
                arguments[v] = call.input(i + 1)
            } else {
                arguments[v] = undefined
            }
        }
        
        let rval = call.output
        b.append(Instruction(operation: Phi(), output: rval, inputs: [undefined]))

        for instr in functionBody {
            let fixedInouts = instr.inouts.map { arguments[$0] ?? $0 }
            let fixedInstr = Instruction(operation: instr.operation, inouts: fixedInouts)
            
            // Return is converted to an assignment to the return value
            if instr.operation is Return {
                b.copy(fixedInstr.input(0), to: rval)
            } else {
                b.append(fixedInstr)
            }
        }
        
        i += 1
        
        // Copy remaining instructions
        while i < program.size {
            assert(!program[i].inputs.contains(function))
            b.append(program[i])
            i += 1
        }
        
        let result = b.finish()
        assert(result.check() == .valid)
        return result
    }
}
