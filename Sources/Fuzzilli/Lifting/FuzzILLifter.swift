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

import Foundation

/// Lifter to convert FuzzIL into its human readable text format
public class FuzzILLifter: Lifter {

    public init() {}

    private func lift(_ v: Variable) -> String {
        return "v\(v.number)"
    }

    private func lift(_ instr : Instruction, with w: inout ScriptWriter) {
        func input(_ n: Int) -> String {
            return lift(instr.input(n))
        }

        func output() -> String {
            return lift(instr.output)
        }

        func innerOutput() -> String {
            return lift(instr.innerOutput)
        }

        switch instr.op.opcode {
        case .loadInteger(let op):
            w.emit("\(output()) <- LoadInteger '\(op.value)'")

        case .loadBigInt(let op):
            w.emit("\(output()) <- LoadBigInt '\(op.value)'")

        case .loadFloat(let op):
            w.emit("\(output()) <- LoadFloat '\(op.value)'")

        case .loadString(let op):
            w.emit("\(output()) <- LoadString '\(op.value)'")

        case .loadRegExp(let op):
            w.emit("\(output()) <- LoadRegExp '\(op.pattern)' '\(op.flags.asString())'")

        case .loadBoolean(let op):
            w.emit("\(output()) <- LoadBoolean '\(op.value)'")

        case .loadUndefined:
            w.emit("\(output()) <- LoadUndefined")

        case .loadNull:
            w.emit("\(output()) <- LoadNull")

        case .loadThis:
            w.emit("\(output()) <- LoadThis")

        case .loadArguments:
            w.emit("\(output()) <- LoadArguments")

        case .createNamedVariable(let op):
            if op.hasInitialValue {
                w.emit("\(output()) <- CreateNamedVariable '\(op.variableName)', '\(op.declarationMode)', \(input(0))")
            } else {
                w.emit("\(output()) <- CreateNamedVariable '\(op.variableName)', '\(op.declarationMode)'")
            }

        case .loadDisposableVariable:
            w.emit("\(output()) <- LoadDisposableVariable \(input(0))")

        case .loadAsyncDisposableVariable:
            w.emit("\(output()) <- LoadAsyncDisposableVariable \(input(0))")

        case .beginObjectLiteral:
            w.emit("BeginObjectLiteral")
            w.increaseIndentionLevel()

        case .objectLiteralAddProperty(let op):
            w.emit("ObjectLiteralAddProperty `\(op.propertyName)`, \(input(0))")

        case .objectLiteralAddElement(let op):
            w.emit("ObjectLiteralAddElement `\(op.index)`, \(input(0))")

        case .objectLiteralAddComputedProperty:
            w.emit("ObjectLiteralAddComputedProperty \(input(0)), \(input(1))")

        case .objectLiteralSetPrototype:
            w.emit("ObjectLiteralSetPrototype \(input(0))")

        case .beginObjectLiteralMethod(let op):
            let params = instr.innerOutputs.map(lift).joined(separator: ", ")
            w.emit("BeginObjectLiteralMethod `\(op.methodName)` -> \(params)")
            w.increaseIndentionLevel()

        case .endObjectLiteralMethod:
            w.decreaseIndentionLevel()
            w.emit("EndObjectLiteralMethod")

        case .beginObjectLiteralComputedMethod:
            let params = instr.innerOutputs.map(lift).joined(separator: ", ")
            w.emit("BeginObjectLiteralComputedMethod \(input(0)) -> \(params)")
            w.increaseIndentionLevel()

        case .endObjectLiteralComputedMethod:
            w.decreaseIndentionLevel()
            w.emit("EndObjectLiteralComputedMethod")

        case .beginObjectLiteralGetter(let op):
            let params = instr.innerOutputs.map(lift).joined(separator: ", ")
            w.emit("BeginObjectLiteralGetter `\(op.propertyName)` -> \(params)")
            w.increaseIndentionLevel()

        case .endObjectLiteralGetter:
            w.decreaseIndentionLevel()
            w.emit("EndObjectLiteralGetter")

        case .beginObjectLiteralSetter(let op):
            let params = instr.innerOutputs.map(lift).joined(separator: ", ")
            w.emit("BeginObjectLiteralSetter `\(op.propertyName)` -> \(params)")
            w.increaseIndentionLevel()

        case .endObjectLiteralSetter:
            w.decreaseIndentionLevel()
            w.emit("EndObjectLiteralSetter")

        case .objectLiteralCopyProperties:
            w.emit("ObjectLiteralCopyProperties \(input(0))")

        case .endObjectLiteral:
            w.decreaseIndentionLevel()
            w.emit("\(output()) <- EndObjectLiteral")

        case .beginClassDefinition(let op):
            var line = "\(output()) <- BeginClassDefinition"
            if op.hasSuperclass {
               line += " \(input(0))"
            }
            w.emit(line)
            w.increaseIndentionLevel()

        case .beginClassConstructor:
           let params = instr.innerOutputs.map(lift).joined(separator: ", ")
           w.emit("BeginClassConstructor -> \(params)")
           w.increaseIndentionLevel()

        case .endClassConstructor:
            w.decreaseIndentionLevel()
            w.emit("EndClassConstructor")

        case .classAddInstanceProperty(let op):
            if op.hasValue {
                w.emit("ClassAddInstanceProperty '\(op.propertyName)' \(input(0))")
            } else {
                w.emit("ClassAddInstanceProperty '\(op.propertyName)'")
            }

        case .classAddInstanceElement(let op):
            if op.hasValue {
                w.emit("ClassAddInstanceElement '\(op.index)' \(input(0))")
            } else {
                w.emit("ClassAddInstanceElement '\(op.index)'")
            }

        case .classAddInstanceComputedProperty(let op):
            if op.hasValue {
                w.emit("ClassAddInstanceComputedProperty \(input(0)) \(input(1))")
            } else {
                w.emit("ClassAddInstanceComputedProperty \(input(0))")
            }

        case .beginClassInstanceMethod(let op):
            let params = instr.innerOutputs.map(lift).joined(separator: ", ")
            w.emit("BeginClassInstanceMethod '\(op.methodName)' -> \(params)")
            w.increaseIndentionLevel()

        case .endClassInstanceMethod:
            w.decreaseIndentionLevel()
            w.emit("EndClassInstanceMethod")

        case .beginClassInstanceGetter(let op):
            let params = instr.innerOutputs.map(lift).joined(separator: ", ")
            w.emit("BeginClassInstanceGetter `\(op.propertyName)` -> \(params)")
            w.increaseIndentionLevel()

        case .endClassInstanceGetter:
            w.decreaseIndentionLevel()
            w.emit("EndClassInstanceGetter")

        case .beginClassInstanceSetter(let op):
            let params = instr.innerOutputs.map(lift).joined(separator: ", ")
            w.emit("BeginClassInstanceSetter `\(op.propertyName)` -> \(params)")
            w.increaseIndentionLevel()

        case .endClassInstanceSetter:
            w.decreaseIndentionLevel()
            w.emit("EndClassInstanceSetter")

        case .classAddStaticProperty(let op):
            if op.hasValue {
                w.emit("ClassAddStaticProperty '\(op.propertyName)' \(input(0))")
            } else {
                w.emit("ClassAddStaticProperty '\(op.propertyName)'")
            }

        case .classAddStaticElement(let op):
            if op.hasValue {
                w.emit("ClassAddStaticElement '\(op.index)' \(input(0))")
            } else {
                w.emit("ClassAddStaticElement '\(op.index)'")
            }

        case .classAddStaticComputedProperty(let op):
            if op.hasValue {
                w.emit("ClassAddStaticComputedProperty \(input(0)) \(input(1))")
            } else {
                w.emit("ClassAddStaticComputedProperty \(input(0))")
            }

        case .beginClassStaticInitializer:
            w.emit("BeginClassStaticInitializer -> \(lift(instr.innerOutput))")
            w.increaseIndentionLevel()

        case .endClassStaticInitializer:
            w.decreaseIndentionLevel()
            w.emit("EndClassStaticInitializer")

        case .beginClassStaticMethod(let op):
            let params = instr.innerOutputs.map(lift).joined(separator: ", ")
            w.emit("BeginClassStaticMethod '\(op.methodName)' -> \(params)")
            w.increaseIndentionLevel()

        case .endClassStaticMethod:
            w.decreaseIndentionLevel()
            w.emit("EndClassStaticMethod")

        case .beginClassStaticGetter(let op):
            let params = instr.innerOutputs.map(lift).joined(separator: ", ")
            w.emit("BeginClassStaticGetter `\(op.propertyName)` -> \(params)")
            w.increaseIndentionLevel()

        case .endClassStaticGetter:
            w.decreaseIndentionLevel()
            w.emit("EndClassStaticGetter")

        case .beginClassStaticSetter(let op):
            let params = instr.innerOutputs.map(lift).joined(separator: ", ")
            w.emit("BeginClassStaticSetter `\(op.propertyName)` -> \(params)")
            w.increaseIndentionLevel()

        case .endClassStaticSetter:
            w.decreaseIndentionLevel()
            w.emit("EndClassStaticSetter")

        case .classAddPrivateInstanceProperty(let op):
            if op.hasValue {
                w.emit("ClassAddPrivateInstanceProperty '\(op.propertyName)' \(input(0))")
            } else {
                w.emit("ClassAddPrivateInstanceProperty '\(op.propertyName)'")
            }

        case .beginClassPrivateInstanceMethod(let op):
            let params = instr.innerOutputs.map(lift).joined(separator: ", ")
            w.emit("BeginClassPrivateInstanceMethod '\(op.methodName)' -> \(params)")
            w.increaseIndentionLevel()

        case .endClassPrivateInstanceMethod:
            w.decreaseIndentionLevel()
            w.emit("EndClassPrivateInstanceMethod")

        case .classAddPrivateStaticProperty(let op):
            if op.hasValue {
                w.emit("ClassAddPrivateStaticProperty '\(op.propertyName)' \(input(0))")
            } else {
                w.emit("ClassAddPrivateStaticProperty '\(op.propertyName)'")
            }

        case .beginClassPrivateStaticMethod(let op):
            let params = instr.innerOutputs.map(lift).joined(separator: ", ")
            w.emit("BeginClassPrivateStaticMethod '\(op.methodName)' -> \(params)")
            w.increaseIndentionLevel()

        case .endClassPrivateStaticMethod:
            w.decreaseIndentionLevel()
            w.emit("EndClassPrivateStaticMethod")

        case .endClassDefinition:
           w.decreaseIndentionLevel()
           w.emit("EndClassDefinition")

        case .createArray:
            let elems = instr.inputs.map(lift).joined(separator: ", ")
            w.emit("\(output()) <- CreateArray [\(elems)]")

        case .createIntArray(let op):
            w.emit("\(instr.output) <- CreateIntArray \(op.values)")

        case .createFloatArray(let op):
            w.emit("\(instr.output) <- CreateFloatArray \(op.values)")

        case .createArrayWithSpread(let op):
            var elems = [String]()
            for (i, v) in instr.inputs.enumerated() {
                if op.spreads[i] {
                    elems.append("...\(lift(v))")
                } else {
                    elems.append(lift(v))
                }
            }
            w.emit("\(output()) <- CreateArrayWithSpread [\(elems.joined(separator: ", "))]")

        case .createTemplateString(let op):
            let parts = op.parts.map({ "'\($0)'" }).joined(separator: ", ")
            let values = instr.inputs.map(lift).joined(separator: ", ")
            w.emit("\(output()) <- CreateTemplateString [\(parts)], [\(values)]")

        case .getProperty(let op):
            let opcode = op.isGuarded ? "GetProperty (guarded)" : "GetProperty"
            w.emit("\(output()) <- \(opcode) \(input(0)), '\(op.propertyName)'")

        case .setProperty(let op):
            w.emit("SetProperty \(input(0)), '\(op.propertyName)', \(input(1))")

        case .updateProperty(let op):
            w.emit("UpdateProperty \(input(0)), '\(op.op.token)', \(input(1))")

        case .deleteProperty(let op):
            let opcode = op.isGuarded ? "DeleteProperty (guarded)" : "DeleteProperty"
            w.emit("\(output()) <- \(opcode) \(input(0)), '\(op.propertyName)'")

        case .configureProperty(let op):
            w.emit("ConfigureProperty \(input(0)), '\(op.propertyName)', '\(op.flags)', '\(op.type)' [\(instr.inputs.suffix(from: 1).map(lift))]")

        case .getElement(let op):
            let opcode = op.isGuarded ? "GetElement (guarded)" : "GetElement"
            w.emit("\(output()) <- \(opcode) \(input(0)), '\(op.index)'")

        case .setElement(let op):
            w.emit("SetElement \(input(0)), '\(op.index)', \(input(1))")

        case .updateElement(let op):
            w.emit("UpdateElement \(instr.input(0)), '\(op.index)', '\(op.op.token)', \(input(1))")

        case .deleteElement(let op):
            let opcode = op.isGuarded ? "DeleteElement (guarded)" : "DeleteElement"
            w.emit("\(output()) <- \(opcode) \(input(0)), '\(op.index)'")

        case .configureElement(let op):
            w.emit("ConfigureElement \(input(0)), '\(op.index)', '\(op.flags)', '\(op.type)' [\(instr.inputs.suffix(from: 1).map(lift))]")

        case .getComputedProperty(let op):
            let opcode = op.isGuarded ? "GetComputedProperty (guarded)" : "GetComputedProperty"
            w.emit("\(output()) <- \(opcode) \(input(0)), \(input(1))")

        case .setComputedProperty:
            w.emit("SetComputedProperty \(input(0)), \(input(1)), \(input(2))")

        case .updateComputedProperty(let op):
            w.emit("UpdateComputedProperty \(input(0)), \(input(1)), '\(op.op.token)',\(input(2))")

        case .deleteComputedProperty(let op):
            let opcode = op.isGuarded ? "DeleteComputedProperty (guarded)" : "DeleteComputedProperty"
            w.emit("\(output()) <- \(opcode) \(input(0)), \(input(1))")

        case .configureComputedProperty(let op):
            w.emit("ConfigureComputedProperty \(input(0)), \(input(1)), '\(op.flags)', '\(op.type)' [\(instr.inputs.suffix(from: 2).map(lift))]")

        case .typeOf:
            w.emit("\(output()) <- TypeOf \(input(0))")

        case .void:
            w.emit("\(output()) <- Void_ \(input(0))")

        case .testInstanceOf:
            w.emit("\(output()) <- TestInstanceOf \(input(0)), \(input(1))")

        case .testIn:
            w.emit("\(output()) <- TestIn \(input(0)), \(input(1))")

        case .beginPlainFunction(let op as BeginAnyFunction),
             .beginArrowFunction(let op as BeginAnyFunction),
             .beginGeneratorFunction(let op as BeginAnyFunction),
             .beginAsyncFunction(let op as BeginAnyFunction),
             .beginAsyncArrowFunction(let op as BeginAnyFunction),
             .beginAsyncGeneratorFunction(let op as BeginAnyFunction):
            let params = instr.innerOutputs.map(lift).joined(separator: ", ")
            w.emit("\(output()) <- \(op.name) -> \(params)")
            w.increaseIndentionLevel()

        case .endPlainFunction(let op as EndAnyFunction),
             .endArrowFunction(let op as EndAnyFunction),
             .endGeneratorFunction(let op as EndAnyFunction),
             .endAsyncFunction(let op as EndAnyFunction),
             .endAsyncArrowFunction(let op as EndAnyFunction),
             .endAsyncGeneratorFunction(let op as EndAnyFunction):
            w.decreaseIndentionLevel()
            w.emit("\(op.name)")

        case .beginConstructor(let op):
            let params = instr.innerOutputs.map(lift).joined(separator: ", ")
            w.emit("\(output()) <- \(op.name) -> \(params)")
            w.increaseIndentionLevel()

        case .endConstructor(let op):
            w.decreaseIndentionLevel()
            w.emit("\(op.name)")

        case .directive(let op):
            w.emit("Directive '\(op.content)'")

        case .return(let op):
            if op.hasReturnValue {
                w.emit("Return \(input(0))")
            } else {
                w.emit("Return")
            }

        case .yield(let op):
            if op.hasArgument {
                w.emit("\(output()) <- Yield \(input(0))")
            } else {
                w.emit("\(output()) <- Yield")
            }

        case .yieldEach:
            w.emit("YieldEach \(input(0))")

        case .await:
            w.emit("\(output()) <- Await \(input(0))")

        case .callFunction(let op):
            let opcode = op.isGuarded ? "CallFunction (guarded)" : "CallFunction"
            w.emit("\(output()) <- \(opcode) \(input(0)), [\(liftCallArguments(instr.variadicInputs))]")

        case .callFunctionWithSpread(let op):
            let opcode = op.isGuarded ? "CallFunctionWithSpread (guarded)" : "CallFunctionWithSpread"
            w.emit("\(output()) <- \(opcode) \(input(0)), [\(liftCallArguments(instr.variadicInputs, spreading: op.spreads))]")

        case .construct(let op):
            let opcode = op.isGuarded ? "Construct (guarded)" : "Construct"
            w.emit("\(output()) <- \(opcode) \(input(0)), [\(liftCallArguments(instr.variadicInputs))]")

        case .constructWithSpread(let op):
            let opcode = op.isGuarded ? "ConstructWithSpread (guarded)" : "ConstructWithSpread"
            w.emit("\(output()) <- \(opcode) \(input(0)), [\(liftCallArguments(instr.variadicInputs, spreading: op.spreads))]")

        case .callMethod(let op):
            let opcode = op.isGuarded ? "CallMethod (guarded)" : "CallMethod"
            w.emit("\(output()) <- \(opcode) \(input(0)), '\(op.methodName)', [\(liftCallArguments(instr.variadicInputs))]")

        case .callMethodWithSpread(let op):
            let opcode = op.isGuarded ? "CallMethodWithSpread (guarded)" : "CallMethodWithSpread"
            w.emit("\(output()) <- \(opcode) \(input(0)), '\(op.methodName)', [\(liftCallArguments(instr.variadicInputs, spreading: op.spreads))]")

        case .callComputedMethod(let op):
            let opcode = op.isGuarded ? "CallComputedMethod (guarded)" : "CallComputedMethod"
            w.emit("\(output()) <- \(opcode) \(input(0)), \(input(1)), [\(liftCallArguments(instr.variadicInputs))]")

        case .callComputedMethodWithSpread(let op):
            let opcode = op.isGuarded ? "CallComputedMethodWithSpread (guarded)" : "CallComputedMethodWithSpread"
            w.emit("\(output()) <- \(opcode) \(input(0)), \(input(1)), [\(liftCallArguments(instr.variadicInputs, spreading: op.spreads))]")

        case .unaryOperation(let op):
            if op.op.isPostfix {
                w.emit("\(output()) <- UnaryOperation \(input(0)), '\(op.op.token)'")
            } else {
                w.emit("\(output()) <- UnaryOperation '\(op.op.token)', \(input(0))")
            }

        case .binaryOperation(let op):
            w.emit("\(output()) <- BinaryOperation \(input(0)), '\(op.op.token)', \(input(1))")

        case .ternaryOperation:
            w.emit("\(output()) <- TernaryOperation \(input(0)), \(input(1)), \(input(2))")

        case .reassign:
            w.emit("Reassign \(input(0)), \(input(1))")

        case .update(let op):
            w.emit("Update \(instr.input(0)), '\(op.op.token)', \(input(1))")

        case .dup:
            w.emit("\(output()) <- Dup \(input(0))")

        case .destructArray(let op):
            let outputs = instr.outputs.map(lift)
            w.emit("[\(liftArrayDestructPattern(indices: op.indices, outputs: outputs, hasRestElement: op.lastIsRest))] <- DestructArray \(input(0))")

        case .destructArrayAndReassign(let op):
            let outputs = instr.inputs.dropFirst().map(lift)
            w.emit("[\(liftArrayDestructPattern(indices: op.indices, outputs: outputs, hasRestElement: op.lastIsRest))] <- DestructArrayAndReassign \(input(0))")

        case .destructObject(let op):
            let outputs = instr.outputs.map(lift)
            w.emit("{\(liftObjectDestructPattern(properties: op.properties, outputs: outputs, hasRestElement: op.hasRestElement))} <- DestructObject \(input(0))")

        case .destructObjectAndReassign(let op):
            let outputs = instr.inputs.dropFirst().map(lift)
            w.emit("{\(liftObjectDestructPattern(properties: op.properties, outputs: outputs, hasRestElement: op.hasRestElement))} <- DestructObjectAndReassign \(input(0))")

        case .compare(let op):
            w.emit("\(output()) <- Compare \(input(0)), '\(op.op.token)', \(input(1))")

        case .eval(let op):
            let args = instr.inputs.map(lift).joined(separator: ", ")
            if op.hasOutput {
                w.emit("\(output()) <- Eval '\(op.code)', [\(args)]")
            } else {
                w.emit("Eval '\(op.code)', [\(args)]")
            }

        case .explore:
            let arguments = instr.inputs.suffix(from: 1).map(lift).joined(separator: ", ")
            w.emit("Explore \(instr.input(0)), [\(arguments)]")

        case .probe:
            w.emit("Probe \(instr.input(0))")

        case .fixup(let op):
            if op.hasOutput {
                w.emit("\(output()) <- Fixup \(op.id)")
            } else {
                w.emit("Fixup \(op.id)")
            }

        case .beginWith:
            w.emit("BeginWith \(input(0))")
            w.increaseIndentionLevel()

        case .endWith:
            w.decreaseIndentionLevel()
            w.emit("EndWith")

        case .nop:
            w.emit("Nop")

        case .beginIf(let op):
            let mode = op.inverted ? "(inverted) " : ""
            w.emit("BeginIf \(mode)\(input(0))")
            w.increaseIndentionLevel()

        case .beginElse:
            w.decreaseIndentionLevel()
            w.emit("BeginElse")
            w.increaseIndentionLevel()

        case .endIf:
            w.decreaseIndentionLevel()
            w.emit("EndIf")

        case .beginSwitch:
            w.emit("BeginSwitch \(input(0))")
            w.increaseIndentionLevel()

        case .beginSwitchCase:
            w.emit("BeginSwitchCase \(input(0))")
            w.increaseIndentionLevel()

        case .beginSwitchDefaultCase:
            w.emit("BeginSwitchDefaultCase")
            w.increaseIndentionLevel()

        case .endSwitchCase(let op):
            w.decreaseIndentionLevel()
            w.emit("EndSwitchCase \(op.fallsThrough ? "fallsThrough" : "")")

        case .endSwitch:
            w.decreaseIndentionLevel()
            w.emit("EndSwitch")

        case .callSuperConstructor:
           w.emit("CallSuperConstructor [\(liftCallArguments(instr.variadicInputs))]")

        case .callSuperMethod(let op):
           w.emit("\(output()) <- CallSuperMethod '\(op.methodName)', [\(liftCallArguments(instr.variadicInputs))]")

        case .getPrivateProperty(let op):
           w.emit("\(output()) <- GetPrivateProperty '\(op.propertyName)'")

        case .setPrivateProperty(let op):
           w.emit("SetPrivateProperty '\(op.propertyName)', \(input(0))")

        case .updatePrivateProperty(let op):
            w.emit("UpdatePrivateProperty '\(op.propertyName)', '\(op.op.token)', \(input(0))")

        case .callPrivateMethod(let op):
            w.emit("\(output()) <- CallPrivateMethod \(input(0)), '\(op.methodName)', [\(liftCallArguments(instr.variadicInputs))]")

        case .getSuperProperty(let op):
           w.emit("\(output()) <- GetSuperProperty '\(op.propertyName)'")

        case .setSuperProperty(let op):
           w.emit("SetSuperProperty '\(op.propertyName)', \(input(0))")

        case .getComputedSuperProperty(_):
            w.emit("\(output()) <- GetComputedSuperProperty \(input(0))")

        case .setComputedSuperProperty(_):
            w.emit("SetComputedSuperProperty \(input(0)), \(input(1))")

        case .updateSuperProperty(let op):
            w.emit("UpdateSuperProperty '\(op.propertyName)', '\(op.op.token)', \(input(0))")

        case .beginWhileLoopHeader:
            w.emit("BeginWhileLoopHeader")
            w.increaseIndentionLevel()

        case .beginWhileLoopBody:
            w.decreaseIndentionLevel()
            w.emit("BeginWhileLoopBody \(input(0))")
            w.increaseIndentionLevel()

        case .endWhileLoop:
            w.decreaseIndentionLevel()
            w.emit("EndWhileLoop")

        case .beginDoWhileLoopBody:
            w.emit("BeginDoWhileLoopBody")
            w.increaseIndentionLevel()

        case .beginDoWhileLoopHeader:
            w.decreaseIndentionLevel()
            w.emit("BeginDoWhileLoopHeader")
            w.increaseIndentionLevel()

        case .endDoWhileLoop:
            w.decreaseIndentionLevel()
            w.emit("EndDoWhileLoop \(input(0))")

        case .beginForLoopInitializer:
            w.emit("BeginForLoopInitializer")
            w.increaseIndentionLevel()

        case .beginForLoopCondition(let op):
            w.decreaseIndentionLevel()
            if op.numLoopVariables > 0 {
                let loopVariables = instr.innerOutputs.map(lift).joined(separator: ", ")
                w.emit("BeginForLoopCondition -> \(loopVariables)")
            } else {
                w.emit("BeginForLoopCondition")
            }
            w.increaseIndentionLevel()

        case .beginForLoopAfterthought(let op):
            w.decreaseIndentionLevel()
            if op.numLoopVariables > 0 {
                let loopVariables = instr.innerOutputs.map(lift).joined(separator: ", ")
                w.emit("BeginForLoopAfterthought \(input(0)) -> \(loopVariables)")
            } else {
                w.emit("BeginForLoopAfterthought \(input(0))")
            }
            w.increaseIndentionLevel()

        case .beginForLoopBody(let op):
            w.decreaseIndentionLevel()
            if op.numLoopVariables > 0 {
                let loopVariables = instr.innerOutputs.map(lift).joined(separator: ", ")
                w.emit("BeginForLoopBody -> \(loopVariables)")
            } else {
                w.emit("BeginForLoopBody")
            }
            w.increaseIndentionLevel()

        case .endForLoop:
            w.decreaseIndentionLevel()
            w.emit("EndForLoop")

        case .beginForInLoop:
            w.emit("BeginForInLoop \(input(0)) -> \(innerOutput())")
            w.increaseIndentionLevel()

        case .endForInLoop:
            w.decreaseIndentionLevel()
            w.emit("EndForInLoop")

        case .beginForOfLoop:
            w.emit("BeginForOfLoop \(input(0)) -> \(innerOutput())")
            w.increaseIndentionLevel()

        case .beginForOfLoopWithDestruct(let op):
            let outputs = instr.innerOutputs.map(lift)
            w.emit("BeginForOfLoopWithDestruct \(input(0)) -> [\(liftArrayDestructPattern(indices: op.indices, outputs: outputs, hasRestElement: op.hasRestElement))]")
            w.increaseIndentionLevel()

        case .endForOfLoop:
            w.decreaseIndentionLevel()
            w.emit("EndForOfLoop")

        case .beginRepeatLoop(let op):
            if op.exposesLoopCounter {
                w.emit("BeginRepeatLoop '\(op.iterations)' -> \(innerOutput())")
            } else {
                w.emit("BeginRepeatLoop '\(op.iterations)'")
            }
            w.increaseIndentionLevel()

        case .endRepeatLoop:
            w.decreaseIndentionLevel()
            w.emit("EndRepeatLoop")

        case .loopBreak,
             .switchBreak:
            w.emit("Break")

        case .loopContinue:
            w.emit("Continue")

        case .beginTry:
            w.emit("BeginTry")
            w.increaseIndentionLevel()

        case .beginCatch:
            w.decreaseIndentionLevel()
            w.emit("BeginCatch -> \(innerOutput())")
            w.increaseIndentionLevel()

        case .beginFinally:
            w.decreaseIndentionLevel()
            w.emit("BeginFinally")
            w.increaseIndentionLevel()

        case .endTryCatchFinally:
            w.decreaseIndentionLevel()
            w.emit("EndTryCatch")

        case .throwException:
            w.emit("ThrowException \(input(0))")

        case .beginCodeString:
            w.emit("\(output()) <- BeginCodeString")
            w.increaseIndentionLevel()

        case .endCodeString:
            w.decreaseIndentionLevel()
            w.emit("EndCodeString")

        case .beginBlockStatement:
            w.emit("BeginBlockStatement")
            w.increaseIndentionLevel()

        case .endBlockStatement:
            w.decreaseIndentionLevel()
            w.emit("EndBlockStatement")

        case .loadNewTarget:
            w.emit("\(output()) <- LoadNewTarget")

        case .beginWasmModule:
            w.emit("BeginWasmModule")
            w.increaseIndentionLevel()

        case .endWasmModule:
            w.decreaseIndentionLevel()
            w.emit("\(output()) <- EndWasmModule")

        case .createWasmGlobal(let op):
        let isMutable = op.isMutable ? ", mutable" : ""
            w.emit("\(output()) <- CreateWasmGlobal \(op.value.typeString()): \(op.value.valueToString())\(isMutable)")

        case .createWasmMemory(let op):
            let maxPagesStr = op.memType.limits.max != nil ? "\(op.memType.limits.max!)" : ""
            let isMem64Str = op.memType.isMemory64 ? " memory64" : ""
            let sharedStr = op.memType.isShared ? " shared" : ""
            w.emit("\(output()) <- CreateWasmMemory [\(op.memType.limits.min),\(maxPagesStr)],\(isMem64Str)\(sharedStr)")

        case .createWasmTable(let op):
            var maxSizeStr = ""
            if let maxSize = op.tableType.limits.max {
                maxSizeStr = "\(maxSize)"
            }
            w.emit("\(output()) <- CreateWasmTable \(op.tableType.elementType) [\(op.tableType.limits.min),\(maxSizeStr)]")

        case .createWasmJSTag(_):
            w.emit("\(output()) <- CreateWasmJSTag")

        case .createWasmTag(let op):
            w.emit("\(output()) <- CreateWasmTag \(op.parameters)")

        case .wrapPromising(_):
            w.emit("\(output()) <- WrapPromising \(input(0))")

        case .wrapSuspending(_):
            w.emit("\(output()) <- WrapSuspending \(input(0))")

        case .bindMethod(_):
            w.emit("\(output()) <- BindMethod \(input(0))")

        // Wasm Instructions

        case .beginWasmFunction(let op):
            // TODO(cffsmith): do this properly?
            w.emit("BeginWasmFunction (\(op.signature)) -> [\(liftCallArguments(instr.innerOutputs))]")
            w.increaseIndentionLevel()

        case .endWasmFunction:
            w.decreaseIndentionLevel()
            w.emit("\(output()) <- EndWasmFunction")

        case .wasmDefineGlobal(let op):
            w.emit("\(output()) <- WasmDefineGlobal \(op.wasmGlobal)")

        case .wasmDefineTable(let op):
            let entries = op.definedEntryIndices.enumerated().map { index, entry in
                "\(entry) : \(input(index))"
            }.joined(separator: ", ")
            w.emit("\(output()) <- WasmDefineTable \(op.tableType.elementType), (\(op.tableType.limits.min), \(String(describing: op.tableType.limits.max))), [\(entries)]")

        case .wasmDefineMemory(let op):
            assert(op.wasmMemory.isWasmMemoryType)
            let mem = op.wasmMemory.wasmMemoryType!
            let maxPagesStr = mem.limits.max != nil ? "\(mem.limits.max!)" : ""
            let isMem64Str = mem.isMemory64 ? " memory64" : ""
            let sharedStr = mem.isShared ? " shared" : ""
            w.emit("\(output()) <- WasmDefineMemory [\(mem.limits.min),\(maxPagesStr)],\(isMem64Str)\(sharedStr)")

        case .wasmDefineTag(let op):
            w.emit("\(output()) <- WasmDefineTag \(op.parameters)")

        case .wasmLoadGlobal(_):
            w.emit("\(output()) <- WasmLoadGlobal \(input(0))")

        case .wasmTableGet(_):
            w.emit("\(output()) <- WasmTableGet \(input(0))[\(input(1))]")

        case .wasmTableSet(_):
            w.emit("WasmTabletSet \(input(0))[\(input(1))] <- \(input(2))")

        case .wasmMemoryLoad(let op):
            w.emit("\(output()) <- WasmMemoryLoad '\(op.loadType)' \(input(0))[\(input(1)) + \(op.staticOffset)]")

        case .wasmMemoryStore(let op):
            w.emit("WasmMemoryStore '\(op.storeType)' \(input(0))[\(input(1)) + \(op.staticOffset)] <- \(input(2))")

        case .wasmStoreGlobal(_):
            w.emit("WasmStoreGlobal \(input(0)) <- \(input(1))")

        case .consti64(let op):
            w.emit("\(output()) <- Consti64 '\(op.value)'")

        case .consti32(let op):
            w.emit("\(output()) <- Consti32 '\(op.value)'")

        case .constf32(let op):
            w.emit("\(output()) <- Constf32 '\(op.value)'")

        case .constf64(let op):
            w.emit("\(output()) <- Constf64 '\(op.value)'")

        case .wasmi64BinOp(let op):
            w.emit("\(output()) <- Wasmi64BinOp \(input(0)) \(op.binOpKind) \(input(1))")

        case .wasmi32BinOp(let op):
            w.emit("\(output()) <- Wasmi32BinOp \(input(0)) \(op.binOpKind) \(input(1))")

        case .wasmf64BinOp(let op):
            w.emit("\(output()) <- Wasmf64BinOp \(input(0)) \(op.binOpKind) \(input(1))")

        case .wasmf32BinOp(let op):
            w.emit("\(output()) <- Wasmf32BinOp \(input(0)) \(op.binOpKind) \(input(1))")

        case .wasmi64CompareOp(let op):
            w.emit("\(output()) <- Wasmi64CompareOp \(input(0)) \(op.compareOpKind) \(input(1))")

        case .wasmi32CompareOp(let op):
            w.emit("\(output()) <- Wasmi32CompareOp \(input(0)) \(op.compareOpKind) \(input(1))")

        case .wasmf64CompareOp(let op):
            w.emit("\(output()) <- Wasmf64CompareOp \(input(0)) \(op.compareOpKind) \(input(1))")

        case .wasmf32CompareOp(let op):
            w.emit("\(output()) <- Wasmf32CompareOp \(input(0)) \(op.compareOpKind) \(input(1))")

        case .wasmi64EqualZero(_):
            w.emit("\(output()) <- Wasmi64EqualZero \(input(0))")

        case .wasmi32EqualZero(_):
            w.emit("\(output()) <- Wasmi32EqualZero \(input(0))")

        case .wasmi64UnOp(let op):
            w.emit("\(output()) <- Wasmi64UnOp \(op.unOpKind)(\(input(0)))")

        case .wasmi32UnOp(let op):
            w.emit("\(output()) <- Wasmi32UnOp \(op.unOpKind)(\(input(0)))")

        case .wasmf64UnOp(let op):
            w.emit("\(output()) <- Wasmf64UnOp \(op.unOpKind)(\(input(0)))")

        case .wasmf32UnOp(let op):
            w.emit("\(output()) <- Wasmf32UnOp \(op.unOpKind)(\(input(0)))")

        // Numerical Conversion Operations
        case .wasmWrapi64Toi32(_):
            w.emit("\(output()) <- WasmWrapi64Toi32 \(input(0))")
        case .wasmTruncatef32Toi32(let op):
            w.emit("\(output()) <- WasmTruncatef32Toi32 \(input(0)) (\(op.isSigned ? "signed" : "unsigned"))")
        case .wasmTruncatef64Toi32(let op):
            w.emit("\(output()) <- WasmTruncatef64Toi32 \(input(0)) (\(op.isSigned ? "signed" : "unsigned"))")
        case .wasmExtendi32Toi64(let op):
            w.emit("\(output()) <- WasmExtendi32Toi64 \(input(0)) (\(op.isSigned ? "signed" : "unsigned"))")
        case .wasmTruncatef32Toi64(let op):
            w.emit("\(output()) <- WasmTruncatef32Toi64 \(input(0)) (\(op.isSigned ? "signed" : "unsigned"))")
        case .wasmTruncatef64Toi64(let op):
            w.emit("\(output()) <- WasmTruncatef64Toi64 \(input(0)) (\(op.isSigned ? "signed" : "unsigned"))")
        case .wasmConverti32Tof32(let op):
            w.emit("\(output()) <- WasmConverti32Tof32 \(input(0)) (\(op.isSigned ? "signed" : "unsigned"))")
        case .wasmConverti64Tof32(let op):
            w.emit("\(output()) <- WasmConverti64Tof32 \(input(0)) (\(op.isSigned ? "signed" : "unsigned"))")
        case .wasmDemotef64Tof32(_):
            w.emit("\(output()) <- WasmDemotef64Tof32 \(input(0))")
        case .wasmConverti32Tof64(let op):
            w.emit("\(output()) <- WasmConverti32Tof64 \(input(0)) (\(op.isSigned ? "signed" : "unsigned"))")
        case .wasmConverti64Tof64(let op):
            w.emit("\(output()) <- WasmConverti64Tof64 \(input(0)) (\(op.isSigned ? "signed" : "unsigned"))")
        case .wasmPromotef32Tof64(_):
            w.emit("\(output()) <- WasmPromotef32Tof64 \(input(0))")
        case .wasmReinterpretf32Asi32(_):
            w.emit("\(output()) <- WasmReinterpretf32Asi32 \(input(0))")
        case .wasmReinterpretf64Asi64(_):
            w.emit("\(output()) <- WasmReinterpretf64Asi64 \(input(0))")
        case .wasmReinterpreti32Asf32(_):
            w.emit("\(output()) <- WasmReinterpreti32Asf32 \(input(0))")
        case .wasmReinterpreti64Asf64(_):
            w.emit("\(output()) <- WasmReinterpreti64Asf64 \(input(0))")
        case .wasmSignExtend8Intoi32(_):
            w.emit("\(output()) <- WasmSignExtend8Intoi32 \(input(0))")
        case .wasmSignExtend16Intoi32(_):
            w.emit("\(output()) <- WasmSignExtend16Intoi32 \(input(0))")
        case .wasmSignExtend8Intoi64(_):
            w.emit("\(output()) <- WasmSignExtend8Intoi64 \(input(0))")
        case .wasmSignExtend16Intoi64(_):
            w.emit("\(output()) <- WasmSignExtend16Intoi64 \(input(0))")
        case .wasmSignExtend32Intoi64(_):
            w.emit("\(output()) <- WasmSignExtend32Intoi64 \(input(0))")
        case .wasmTruncateSatf32Toi32(let op):
            w.emit("\(output()) <- WasmTruncateSatf32Toi32 \(input(0)) (\(op.isSigned ? "signed" : "unsigned"))")
        case .wasmTruncateSatf64Toi32(let op):
            w.emit("\(output()) <- WasmTruncateSatf64Toi32 \(input(0)) (\(op.isSigned ? "signed" : "unsigned"))")
        case .wasmTruncateSatf32Toi64(let op):
            w.emit("\(output()) <- WasmTruncateSatf32Toi64 \(input(0)) (\(op.isSigned ? "signed" : "unsigned"))")
        case .wasmTruncateSatf64Toi64(let op):
            w.emit("\(output()) <- WasmTruncateSatf64Toi64 \(input(0)) (\(op.isSigned ? "signed" : "unsigned"))")

        case .wasmReturn(let op):
            if op.numInputs > 0 {
                w.emit("WasmReturn \(input(0))")
            } else {
                w.emit("WasmReturn")
            }

        case .wasmJsCall(let op):
            var arguments: [Variable] = []
            for i in 0..<op.functionSignature.parameters.count {
                arguments.append(instr.input(i + 1))
            }
            if op.functionSignature.outputType.Is(.nothing) {
                w.emit("WasmJsCall(\(op.functionSignature)) \(instr.input(0)) [\(liftCallArguments(arguments[...]))]")
            } else {
                w.emit("\(output()) <- WasmJsCall(\(op.functionSignature)) \(instr.input(0)) [\(liftCallArguments(arguments[...]))]")
            }

        case .wasmBeginBlock(let op):
            // TODO(cffsmith): Maybe lift labels as e.g. L7 or something like that?
            let inputs = instr.inputs.map(lift).joined(separator: ", ")
            w.emit("WasmBeginBlock (\(op.signature)) [\(inputs)] -> L:\(instr.innerOutput(0)) [\(liftCallArguments(instr.innerOutputs(1...)))]")
            w.increaseIndentionLevel()

        case .wasmEndBlock(let op):
            w.decreaseIndentionLevel()
            let inputs = instr.inputs.map(lift).joined(separator: ", ")
            if op.numOutputs > 0 {
                w.emit("\(output()) <- WasmEndBlock \(inputs)")
            } else {
                w.emit("WasmEndBlock \(inputs)")
            }

        case .wasmBeginLoop(let op):
            let inputs = instr.inputs.map(lift).joined(separator: ", ")
            w.emit("WasmBeginLoop (\(op.signature)) [\(inputs)] -> L:\(instr.innerOutput(0)) [\(liftCallArguments(instr.innerOutputs(1...)))]")
            w.increaseIndentionLevel()

        case .wasmEndLoop(let op):
            w.decreaseIndentionLevel()
            let inputs = instr.inputs.map(lift).joined(separator: ", ")
            if op.numOutputs > 0 {
                w.emit("\(output()) <- WasmEndLoop \(inputs)")
            } else {
                w.emit("WasmEndLoop \(inputs)")
            }

        case .wasmBeginTry(let op):
            let inputs = instr.inputs.map(lift).joined(separator: ", ")
            w.emit("WasmBeginTry (\(op.signature)) [\(inputs)] -> L:\(instr.innerOutput(0)) [\(liftCallArguments(instr.innerOutputs(1...)))]")
            w.increaseIndentionLevel()

        case .wasmBeginCatchAll(_):
            assert(instr.numOutputs == 0)
            w.decreaseIndentionLevel()
            let inputs = instr.inputs.map(lift).joined(separator: ", ")
            w.emit("WasmBeginCatchAll [\(inputs)] -> L:\(instr.innerOutput(0))")
            w.increaseIndentionLevel()
        case .wasmBeginCatch(_):
            assert(instr.numOutputs == 0)
            w.decreaseIndentionLevel()
            w.emit("WasmBeginCatch \(input(0)) [\(instr.numInputs > 1 ? input(1) : "")] -> L:\(instr.innerOutput(0)) E:\(instr.innerOutput(1)) [\(liftCallArguments(instr.innerOutputs(2...)))]")
            w.increaseIndentionLevel()

        case .wasmEndTry(let op):
            w.decreaseIndentionLevel()
            let outputPrefix = op.numOutputs > 0 ? "\(output()) <- " : ""
            let inputs = instr.inputs.map(lift).joined(separator: ", ")
            w.emit("\(outputPrefix)WasmEndTry [\(inputs)]")

        case .wasmThrow(_):
            w.emit("WasmThrow \(instr.inputs.map(lift).joined(separator: ", "))")

        case .wasmRethrow(_):
            w.emit("WasmRethrow \(instr.input(0))")

        case .wasmBeginTryDelegate(let op):
            w.emit("WasmBeginTryDelegate L:\(instr.innerOutput(0)) [\(liftCallArguments(instr.innerOutputs(1...)))] (\(op.signature))")
            w.increaseIndentionLevel()

        case .wasmEndTryDelegate(_):
            w.decreaseIndentionLevel()
            w.emit("WasmEndTryDelegate \(input(0))")

        case .wasmReassign(_):
            w.emit("\(input(0)) <- WasmReassign \(input(1))")

        case .wasmBranch(_):
            w.emit("wasmBranch: \(instr.inputs.map(lift).joined(separator: ", "))")

        case .wasmBranchIf(_):
            w.emit("wasmBranchIf \(instr.input(1)), \(([instr.input(0)] + Array(instr.inputs)[2...]).map(lift).joined(separator: ", "))")

        case .wasmBeginIf(let op):
            let inputs = instr.inputs.map(lift).joined(separator: ", ")
            w.emit("wasmBeginIf (\(op.signature)) [\(inputs)] -> L:\(instr.innerOutput(0)) [\(liftCallArguments(instr.innerOutputs(1...)))]")
            w.increaseIndentionLevel()

        case .wasmBeginElse(_):
            w.decreaseIndentionLevel()
            let inputs = instr.inputs.map(lift).joined(separator: ", ")
            // Note that the signature is printed by the WasmBeginIf, so we skip it here for better
            // readability.
            w.emit("wasmBeginElse [\(inputs)] -> L:\(instr.innerOutput(0)) [\(liftCallArguments(instr.innerOutputs(1...)))]")
            w.increaseIndentionLevel()

        case .wasmEndIf(let op):
            w.decreaseIndentionLevel()
            let inputs = instr.inputs.map(lift).joined(separator: ", ")
            if op.numOutputs > 0 {
                w.emit("\(output()) <- WasmEndIf \(inputs)")
            } else {
                w.emit("WasmEndIf \(inputs)")
            }

        case .print:
            w.emit("Print \(input(0))")

        case .wasmNop:
            w.emit("WasmNop")

        case .wasmUnreachable:
            w.emit("WasmUnreachable")

        case .wasmSelect(let op):
            w.emit("\(output()) <- WasmSelect[\(op.type)] \(input(2)) ? \(input(0)) : \(input(1))")

        case .constSimd128(let op):
            w.emit("\(output()) <- ConstSimd128 \(op.value)")

        case .wasmSimd128IntegerUnOp(let op):
            w.emit("\(output()) <- WasmSimd128IntegerUnOp \(op.shape) \(op.unOpKind) \(input(0))")

        case .wasmSimd128IntegerBinOp(let op):
            w.emit("\(output()) <- WasmSimd128IntegerBinOp \(op.shape) \(op.binOpKind) \(input(0)) \(input(1))")

        case .wasmSimd128FloatUnOp(let op):
            w.emit("\(output()) <- WasmSimd128FloatUnOp \(op.shape).\(op.unOpKind) \(input(0))")

        case .wasmSimd128FloatBinOp(let op):
            w.emit("\(output()) <- WasmSimd128FloatBinOp \(op.shape).\(op.binOpKind) \(input(0)) \(input(1))")

        case .wasmSimd128Compare(let op):
            w.emit("\(output()) <- WasmSimd128Compare \(op.shape) \(op.compareOpKind) \(input(0)) \(input(1))")

        case .wasmI64x2Splat(_):
            w.emit("\(output()) <- WasmI64x2Splat \(input(0))")

        case .wasmI64x2ExtractLane(let op):
            w.emit("\(output()) <- WasmI64x2ExtractLane \(input(0)) \(op.lane)")

        case .wasmSimdLoad(let op):
            w.emit("\(output()) <- WasmSimdLoad \(op.kind) \(input(0)) + \(op.staticOffset)")

        default:
            fatalError("No FuzzIL lifting for this operation!")
        }

    }

    public func lift(_ program: Program, withOptions options: LiftingOptions) -> String {
        var w = ScriptWriter()

        if options.contains(.includeComments), let header = program.comments.at(.header) {
            w.emitComment(header)
        }

        for instr in program.code {
            if options.contains(.includeComments), let comment = program.comments.at(.instruction(instr.index)) {
                w.emitComment(comment)
            }

            lift(instr, with: &w)
        }

        if options.contains(.includeComments), let footer = program.comments.at(.footer) {
            w.emitComment(footer)
        }

        return w.code
    }

    public func lift(_ code: Code) -> String {
        var w = ScriptWriter()

        for instr in code {
            lift(instr, with: &w)
        }

        return w.code
    }

    private func liftCallArguments(_ args: ArraySlice<Variable>, spreading spreads: [Bool] = []) -> String {
        var arguments = [String]()
        for (i, v) in args.enumerated() {
            if spreads.count > i && spreads[i] {
                arguments.append("...\(lift(v))")
            } else {
                arguments.append(lift(v))
            }
        }
        return arguments.joined(separator: ", ")
    }

    private func liftArrayDestructPattern(indices: [Int64], outputs: [String], hasRestElement: Bool) -> String {
        assert(indices.count == outputs.count)

        var arrayPattern = ""
        var lastIndex = 0
        for (index64, output) in zip(indices, outputs) {
            let index = Int(index64)
            let skipped = index - lastIndex
            lastIndex = index
            let dots = index == indices.last! && hasRestElement ? "..." : ""
            arrayPattern += String(repeating: ",", count: skipped) + dots + output
        }

        return arrayPattern
    }

    private func liftObjectDestructPattern(properties: [String], outputs: [String], hasRestElement: Bool) -> String {
        assert(outputs.count == properties.count + (hasRestElement ? 1 : 0))

        var objectPattern = ""
        for (property, output) in zip(properties, outputs) {
            objectPattern += "\(property):\(output),"
        }
        if hasRestElement {
            objectPattern += "...\(outputs.last!)"
        }

        return objectPattern
    }
}

