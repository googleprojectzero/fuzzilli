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
            w.emit("\(output()) <- LoadRegExp '\(op.value)' '\(op.flags.asString())'")

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

        case .createObject(let op):
            var properties = [String]()
            for (index, propertyName) in op.propertyNames.enumerated() {
                properties.append("'\(propertyName)':\(input(index))")
            }
            w.emit("\(output()) <- CreateObject [\(properties.joined(separator: ", "))]")

        case .createArray:
            let elems = instr.inputs.map(lift).joined(separator: ", ")
            w.emit("\(output()) <- CreateArray [\(elems)]")

        case .createIntArray(let op):
            w.emit("\(instr.output) <- CreateIntArray \(op.values)")

        case .createFloatArray(let op):
            w.emit("\(instr.output) <- CreateFloatArray \(op.values)")

        case .createObjectWithSpread(let op):
            var properties = [String]()
            for (index, propertyName) in op.propertyNames.enumerated() {
                properties.append("'\(propertyName)':\(input(index))")
            }
            // Remaining ones are spread.
            for v in instr.inputs.dropFirst(properties.count) {
                properties.append("...\(lift(v))")
            }
            w.emit("\(output()) <- CreateObjectWithSpread [\(properties.joined(separator: ", "))]")

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

        case .loadBuiltin(let op):
            w.emit("\(output()) <- LoadBuiltin '\(op.builtinName)'")

        case .loadProperty(let op):
            w.emit("\(output()) <- LoadProperty \(input(0)), '\(op.propertyName)'")

        case .storeProperty(let op):
            w.emit("StoreProperty \(input(0)), '\(op.propertyName)', \(input(1))")

        case .storePropertyWithBinop(let op):
            w.emit("\(input(0)) <- StorePropertyWithBinop '\(op.op.token)', \(input(1))")

        case .deleteProperty(let op):
            w.emit("\(output()) <- DeleteProperty \(input(0)), '\(op.propertyName)'")

        case .configureProperty(let op):
            w.emit("ConfigureProperty \(input(0)), '\(op.propertyName)', '\(op.flags)', '\(op.type)' [\(instr.inputs.suffix(from: 1).map(lift))]")

        case .loadElement(let op):
            w.emit("\(output()) <- LoadElement \(input(0)), '\(op.index)'")

        case .storeElement(let op):
            w.emit("StoreElement \(input(0)), '\(op.index)', \(input(1))")

        case .storeElementWithBinop(let op):
            w.emit("\(instr.input(0)) <- StoreElementWithBinop '\(op.index)', '\(op.op.token)', \(input(1))")

        case .deleteElement(let op):
            w.emit("\(output()) <- DeleteElement \(input(0)), '\(op.index)'")

        case .configureElement(let op):
            w.emit("ConfigureElement \(input(0)), '\(op.index)', '\(op.flags)', '\(op.type)' [\(instr.inputs.suffix(from: 1).map(lift))]")

        case .loadComputedProperty:
            w.emit("\(output()) <- LoadComputedProperty \(input(0)), \(input(1))")

        case .storeComputedProperty:
            w.emit("StoreComputedProperty \(input(0)), \(input(1)), \(input(2))")

        case .storeComputedPropertyWithBinop(let op):
            w.emit("StoreComputedPropertyWithBinop \(input(0)), \(input(1)), '\(op.op.token)',\(input(2))")

        case .deleteComputedProperty:
            w.emit("\(output()) <- DeleteComputedProperty \(input(0)), \(input(1))")

        case .configureComputedProperty(let op):
            w.emit("ConfigureComputedProperty \(input(0)), \(input(1)), '\(op.flags)', '\(op.type)' [\(instr.inputs.suffix(from: 2).map(lift))]")

        case .typeOf:
            w.emit("\(output()) <- TypeOf \(input(0))")

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
            w.emit("\(output()) <- \(op.name) -> \(params)\(op.isStrict ? ", strict" : "")")
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

        case .return:
            w.emit("Return \(input(0))")

        case .yield:
            w.emit("\(output()) <- Yield \(input(0))")

        case .yieldEach:
            w.emit("YieldEach \(input(0))")

        case .await:
            w.emit("\(output()) <- Await \(input(0))")

        case .callFunction:
            w.emit("\(output()) <- CallFunction \(input(0)), [\(liftCallArguments(instr.variadicInputs))]")

        case .callFunctionWithSpread(let op):
            w.emit("\(output()) <- CallFunctionWithSpread \(input(0)), [\(liftCallArguments(instr.variadicInputs, spreading: op.spreads))]")

        case .construct:
            w.emit("\(output()) <- Construct \(input(0)), [\(liftCallArguments(instr.variadicInputs))]")

        case .constructWithSpread(let op):
            w.emit("\(output()) <- ConstructWithSpread \(input(0)), [\(liftCallArguments(instr.variadicInputs, spreading: op.spreads))]")

        case .callMethod(let op):
            w.emit("\(output()) <- CallMethod \(input(0)), '\(op.methodName)', [\(liftCallArguments(instr.variadicInputs))]")

        case .callMethodWithSpread(let op):
            w.emit("\(output()) <- CallMethodWithSpread \(input(0)), '\(op.methodName)', [\(liftCallArguments(instr.variadicInputs, spreading: op.spreads))]")

        case .callComputedMethod:
            w.emit("\(output()) <- CallComputedMethod \(input(0)), \(input(1)), [\(liftCallArguments(instr.variadicInputs))]")

        case .callComputedMethodWithSpread(let op):
            w.emit("\(output()) <- CallComputedMethodWithSpread \(input(0)), \(input(1)), [\(liftCallArguments(instr.variadicInputs, spreading: op.spreads))]")

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

        case .reassignWithBinop(let op):
            w.emit("ReassignWithBinop \(instr.input(0)), '\(op.op.token)', \(input(1))")

        case .dup:
            w.emit("\(output()) <- Dup \(input(0))")

        case .destructArray(let op):
            let outputs = instr.outputs.map(lift)
            w.emit("[\(liftArrayDestructPattern(indices: op.indices, outputs: outputs, hasRestElement: op.hasRestElement))] <- DestructArray \(input(0))")

        case .destructArrayAndReassign(let op):
            let outputs = instr.inputs.dropFirst().map(lift)
            w.emit("[\(liftArrayDestructPattern(indices: op.indices, outputs: outputs, hasRestElement: op.hasRestElement))] <- DestructArrayAndReassign \(input(0))")

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
            w.emit("Eval '\(op.code)', [\(args)]")

        case .explore:
            let arguments = instr.inputs.suffix(from: 1).map(lift).joined(separator: ", ")
            w.emit("Explore \(instr.input(0)), [\(arguments)]")

        case .probe:
            w.emit("Probe \(instr.input(0))")

        case .beginWith:
            w.emit("BeginWith \(input(0))")
            w.increaseIndentionLevel()

        case .endWith:
            w.decreaseIndentionLevel()
            w.emit("EndWith")

        case .loadFromScope(let op):
            w.emit("\(output()) <- LoadFromScope '\(op.id)'")

        case .storeToScope(let op):
            w.emit("StoreToScope '\(op.id)', \(input(0))")

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

        case .beginClass(let op):
           var line = "\(output()) <- BeginClass"
           if instr.hasInputs {
               line += " \(input(0)),"
           }
           line += " \(op.instanceProperties),"
           line += " \(Array(op.instanceMethods.map({ $0.name })))"
           w.emit(line)
           w.increaseIndentionLevel()

        case .beginMethod:
           w.decreaseIndentionLevel()
           let params = instr.innerOutputs.map(lift).joined(separator: ", ")
           w.emit("BeginMethod -> \(params)")
           w.increaseIndentionLevel()

        case .endClass:
           w.decreaseIndentionLevel()
           w.emit("EndClass")

        case .callSuperConstructor:
           w.emit("CallSuperConstructor [\(liftCallArguments(instr.variadicInputs))]")

        case .callSuperMethod(let op):
           w.emit("\(output()) <- CallSuperMethod '\(op.methodName)', [\(liftCallArguments(instr.variadicInputs))]")

        case .loadSuperProperty(let op):
           w.emit("\(output()) <- LoadSuperProperty '\(op.propertyName)'")

        case .storeSuperProperty(let op):
           w.emit("StoreSuperProperty '\(op.propertyName)', \(input(0))")

        case .storeSuperPropertyWithBinop(let op):
            w.emit("StoreSuperPropertyWithBinop '\(op.propertyName)', '\(op.op.token)', \(input(0))")

        case .beginWhileLoop(let op):
            w.emit("BeginWhileLoop \(input(0)), '\(op.comparator.token)', \(input(1))")
            w.increaseIndentionLevel()

        case .endWhileLoop:
            w.decreaseIndentionLevel()
            w.emit("EndWhileLoop")

        case .beginDoWhileLoop(let op):
            w.emit("BeginDoWhileLoop \(input(0)), '\(op.comparator.token)', \(input(1))")
            w.increaseIndentionLevel()

        case .endDoWhileLoop:
            w.decreaseIndentionLevel()
            w.emit("EndDoWhileLoop")

        case .beginForLoop(let op):
            w.emit("BeginForLoop \(input(0)), '\(op.comparator.token)', \(input(1)), '\(op.op.token)', \(input(2)) -> \(innerOutput())")
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

        case .beginForOfWithDestructLoop(let op):
            let outputs = instr.innerOutputs.map(lift)
            w.emit("BeginForOfLoop \(input(0)) -> [\(liftArrayDestructPattern(indices: op.indices, outputs: outputs, hasRestElement: op.hasRestElement))]")
            w.increaseIndentionLevel()

        case .endForOfLoop:
            w.decreaseIndentionLevel()
            w.emit("EndForOfLoop")

        case .beginRepeatLoop(let op):
            w.emit("BeginLoop \(op.iterations) -> \(innerOutput())")
            w.increaseIndentionLevel()

        case .endRepeatLoop:
            w.decreaseIndentionLevel()
            w.emit("EndLoop")

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

        case .print:
            w.emit("Print \(input(0))")
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

