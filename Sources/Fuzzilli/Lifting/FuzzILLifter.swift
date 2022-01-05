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
    
    private func lift(_ instr : Instruction, with w: inout ScriptWriter) {
        func input(_ n: Int) -> Variable {
            return instr.input(n)
        }

        // Helper function to lift destruct array operations
        func liftArrayPattern(indices: [Int], outputs: [String], hasRestElement: Bool) -> String {
            assert(indices.count == outputs.count)

            var arrayPattern = ""
            var lastIndex = 0
            for (index, output) in zip(indices, outputs) {
                let skipped = index - lastIndex
                lastIndex = index
                let dots = index == indices.last! && hasRestElement ? "..." : ""
                arrayPattern += String(repeating: ",", count: skipped) + dots + output
            }

            return arrayPattern
        }

        func liftObjectDestructPattern(properties: [String], outputs: [String], hasRestElement: Bool) -> String {
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

        switch instr.op {
        case let op as LoadInteger:
            w.emit("\(instr.output) <- LoadInteger '\(op.value)'")

        case let op as LoadBigInt:
            w.emit("\(instr.output) <- LoadBigInt '\(op.value)'")

        case let op as LoadFloat:
            w.emit("\(instr.output) <- LoadFloat '\(op.value)'")

        case let op as LoadString:
            w.emit("\(instr.output) <- LoadString '\(op.value)'")

        case let op as LoadRegExp:
            w.emit("\(instr.output) <- LoadRegExp '\(op.value)' '\(op.flags.asString())'")

        case let op as LoadBoolean:
            w.emit("\(instr.output) <- LoadBoolean '\(op.value)'")

        case is LoadUndefined:
            w.emit("\(instr.output) <- LoadUndefined")

        case is LoadNull:
            w.emit("\(instr.output) <- LoadNull")

        case is LoadThis:
            w.emit("\(instr.output) <- LoadThis")

        case is LoadArguments:
            w.emit("\(instr.output) <- LoadArguments")

        case let op as CreateObject:
            var properties = [String]()
            for (index, propertyName) in op.propertyNames.enumerated() {
                properties.append("'\(propertyName)':\(input(index))")
            }
            w.emit("\(instr.output) <- CreateObject [\(properties.joined(separator: ", "))]")

        case is CreateArray:
            let elems = instr.inputs.map({ $0.identifier }).joined(separator: ", ")
            w.emit("\(instr.output) <- CreateArray [\(elems)]")

        case let op as CreateObjectWithSpread:
            var properties = [String]()
            for (index, propertyName) in op.propertyNames.enumerated() {
                properties.append("'\(propertyName)':\(input(index))")
            }
            // Remaining ones are spread.
            for v in instr.inputs.dropFirst(properties.count) {
                properties.append("...\(v)")
            }
            w.emit("\(instr.output) <- CreateObjectWithSpread [\(properties.joined(separator: ", "))]")

        case let op as CreateArrayWithSpread:
            var elems = [String]()
            for (i, v) in instr.inputs.enumerated() {
                if op.spreads[i] {
                    elems.append("...\(v)")
                } else {
                    elems.append(v.identifier)
                }
            }
            w.emit("\(instr.output) <- CreateArrayWithSpread [\(elems.joined(separator: ", "))]")

        case let op as CreateTemplateString:
            let parts = op.parts.map({ "'\($0)'" }).joined(separator: ", ")
            let values = instr.inputs.map({ $0.identifier }).joined(separator: ", ")
            w.emit("\(instr.output) <- CreateTemplateString [\(parts)], [\(values)]")

        case let op as LoadBuiltin:
            w.emit("\(instr.output) <- LoadBuiltin '\(op.builtinName)'")

        case let op as LoadProperty:
            w.emit("\(instr.output) <- LoadProperty \(input(0)), '\(op.propertyName)'")

        case let op as StoreProperty:
            w.emit("StoreProperty \(input(0)), '\(op.propertyName)', \(input(1))")

        case let op as StorePropertyWithBinop:
            w.emit("\(instr.input(0)) <- StorePropertyWithBinop '\(op.op.token)', \(input(1))")

        case let op as DeleteProperty:
            w.emit("\(instr.output) <- DeleteProperty \(input(0)), '\(op.propertyName)'")

        case let op as LoadElement:
            w.emit("\(instr.output) <- LoadElement \(input(0)), '\(op.index)'")

        case let op as StoreElement:
            w.emit("StoreElement \(input(0)), '\(op.index)', \(input(1))")

        case let op as StoreElementWithBinop:
            w.emit("\(instr.input(0)) <- StoreElementWithBinop '\(op.index)', '\(op.op.token)', \(input(1))")

        case let op as DeleteElement:
            w.emit("\(instr.output) <- DeleteElement \(input(0)), '\(op.index)'")

        case is LoadComputedProperty:
            w.emit("\(instr.output) <- LoadComputedProperty \(input(0)), \(input(1))")

        case is StoreComputedProperty:
            w.emit("StoreComputedProperty \(input(0)), \(input(1)), \(input(2))")

        case let op as StoreComputedPropertyWithBinop:
            w.emit("StoreComputedPropertyWithBinop \(input(0)), \(input(1)), '\(op.op.token)',\(input(2))")

        case is DeleteComputedProperty:
            w.emit("\(instr.output) <- DeleteComputedProperty \(input(0)), \(input(1))")

        case is TypeOf:
            w.emit("\(instr.output) <- TypeOf \(input(0))")

        case is InstanceOf:
            w.emit("\(instr.output) <- InstanceOf \(input(0)), \(input(1))")

        case is In:
            w.emit("\(instr.output) <- In \(input(0)), \(input(1))")

        case let op as BeginAnyFunctionDefinition:
            let params = instr.innerOutputs.map({ $0.identifier }).joined(separator: ", ")
            w.emit("\(instr.output) <- \(op.name) -> \(params)\(op.isStrict ? ", strict" : "")")
            w.increaseIndentionLevel()

        case let op as EndAnyFunctionDefinition:
            w.decreaseIndentionLevel()
            w.emit("\(op.name)")

        case is Return:
            w.emit("Return \(input(0))")

        case is Yield:
            w.emit("\(instr.output) <- Yield \(input(0))")

        case is YieldEach:
            w.emit("YieldEach \(input(0))")

        case is Await:
            w.emit("\(instr.output) <- Await \(input(0))")

        case let op as CallMethod:
            var arguments = [String]()
            for (i, v) in instr.inputs.dropFirst().enumerated() {
                if op.spreads[i] {
                    arguments.append("...\(v.identifier)")
                } else {
                    arguments.append(v.identifier)
                }
            }
            w.emit("\(instr.output) <- CallMethod \(input(0)), '\(op.methodName)', [\(arguments.joined(separator: ", "))]")

        case let op as CallComputedMethod:
            var arguments = [String]()
            for (i, v) in instr.inputs.dropFirst(2).enumerated() {
                if op.spreads[i] {
                    arguments.append("...\(v.identifier)")
                } else {
                    arguments.append(v.identifier)
                }
            }
            w.emit("\(instr.output) <- CallComputedMethod \(input(0)), \(input(1)), [\(arguments.joined(separator: ", "))]")

        case let op as CallFunction:
            var arguments = [String]()
            for (i, v) in instr.inputs.dropFirst().enumerated() {
                if op.spreads[i] {
                    arguments.append("...\(v.identifier)")
                } else {
                    arguments.append(v.identifier)
                }
            }
            w.emit("\(instr.output) <- CallFunction \(input(0)), [\(arguments.joined(separator: ", "))]")

        case let op as Construct:
            var arguments = [String]()
            for (i, v) in instr.inputs.dropFirst().enumerated() {
                if op.spreads[i] {
                    arguments.append("...\(v.identifier)")
                } else {
                    arguments.append(v.identifier)
                }
            }
            w.emit("\(instr.output) <- Construct \(input(0)), [\(arguments.joined(separator: ", "))]")

        case let op as UnaryOperation:
            if op.op.isPostfix {
                w.emit("\(instr.output) <- UnaryOperation \(input(0)), '\(op.op.token)'")
            } else {
                w.emit("\(instr.output) <- UnaryOperation '\(op.op.token)', \(input(0))")
            }

        case let op as BinaryOperation:
            w.emit("\(instr.output) <- BinaryOperation \(input(0)), '\(op.op.token)', \(input(1))")

        case let op as ReassignWithBinop:
            w.emit("\(instr.input(0)) <- ReassignWithBinop '\(op.op.token)', \(input(1))")

        case is Dup:
            w.emit("\(instr.output) <- Dup \(input(0))")

        case is Reassign:
            w.emit("Reassign \(input(0)), \(input(1))")

        case let op as DestructArray:
            let outputs = instr.outputs.map({ $0.identifier })
            w.emit("[\(liftArrayPattern(indices: op.indices, outputs: outputs, hasRestElement: op.hasRestElement))] <- DestructArray \(input(0))")

        case let op as DestructArrayAndReassign:
            let outputs = instr.inputs.dropFirst().map({ $0.identifier })        
            w.emit("[\(liftArrayPattern(indices: op.indices, outputs: outputs, hasRestElement: op.hasRestElement))] <- DestructArrayAndReassign \(input(0))")

        case let op as DestructObject:
            let outputs = instr.outputs.map({ $0.identifier })
            w.emit("{\(liftObjectDestructPattern(properties: op.properties, outputs: outputs, hasRestElement: op.hasRestElement))} <- DestructObject \(input(0))")

        case let op as DestructObjectAndReassign:
            let outputs = instr.inputs.dropFirst().map({ $0.identifier })  
            w.emit("{\(liftObjectDestructPattern(properties: op.properties, outputs: outputs, hasRestElement: op.hasRestElement))} <- DestructObjectAndReassign \(input(0))")

        case let op as Compare:
            w.emit("\(instr.output) <- Compare \(input(0)), '\(op.op.token)', \(input(1))")

        case is ConditionalOperation:
            w.emit("\(instr.output) <- \(input(0)), \(input(1)), \(input(2))")

        case let op as Eval:
            let args = instr.inputs.map({ $0.identifier }).joined(separator: ", ")
            w.emit("Eval '\(op.code)', [\(args)]")

        case is BeginWith:
            w.emit("BeginWith \(input(0))")
            w.increaseIndentionLevel()

        case is EndWith:
            w.decreaseIndentionLevel()
            w.emit("EndWith")

        case let op as LoadFromScope:
            w.emit("\(instr.output) <- LoadFromScope '\(op.id)'")

        case let op as StoreToScope:
            w.emit("StoreToScope '\(op.id)', \(input(0))")

        case is Nop:
            w.emit("Nop")

        case is BeginIf:
            w.emit("BeginIf \(input(0))")
            w.increaseIndentionLevel()

        case is BeginElse:
            w.decreaseIndentionLevel()
            w.emit("BeginElse")
            w.increaseIndentionLevel()

        case is EndIf:
            w.decreaseIndentionLevel()
            w.emit("EndIf")

        case let op as BeginSwitch:
            w.emit("BeginSwitch \(input(0))\(op.isDefaultCase ? "" : input(1).description)")
            w.increaseIndentionLevel()

        case let op as BeginSwitchCase:
            w.decreaseIndentionLevel()
            w.emit("BeginSwitchCase \(op.isDefaultCase ? "" : input(0).description) \(op.previousCaseFallsThrough ? "previousCaseFallsThrough" : "")")
            w.increaseIndentionLevel()

        case is EndSwitch:
            w.decreaseIndentionLevel()
            w.emit("EndSwitch")

       case let op as BeginClassDefinition:
           var line = "\(instr.output) <- BeginClassDefinition"
           if instr.hasInputs {
               line += " \(input(0)),"
           }
           line += " \(op.instanceProperties),"
           line += " \(Array(op.instanceMethods.map({ $0.name })))"
           w.emit(line)
           w.increaseIndentionLevel()

       case let op as BeginMethodDefinition:
           w.decreaseIndentionLevel()
           let params = instr.innerOutputs.map({ $0.identifier }).joined(separator: ", ")
           w.emit("\(op.name) -> \(params)")
           w.increaseIndentionLevel()

       case is EndClassDefinition:
           w.decreaseIndentionLevel()
           w.emit("EndClassDefinition")

       case let op as CallSuperConstructor:
           var arguments = [String]()
           for (i, v) in instr.inputs.enumerated() {
               if op.spreads[i] {
                   arguments.append("...\(v.identifier)")
               } else {
                   arguments.append(v.identifier)
               }
           }
           w.emit("CallSuperConstructor [\(arguments.joined(separator: ", "))]")

       case let op as CallSuperMethod:
           let arguments = instr.inputs.map({ $0.identifier })
           w.emit("\(instr.output) <- CallSuperMethod '\(op.methodName)', [\(arguments.joined(separator: ", "))]")

       case let op as LoadSuperProperty:
           w.emit("\(instr.output) <- LoadSuperProperty '\(op.propertyName)'")

       case let op as StoreSuperProperty:
           w.emit("StoreSuperProperty '\(op.propertyName)', \(input(0))")

        case let op as StoreSuperPropertyWithBinop:
            w.emit("StoreSuperPropertyWithBinop '\(op.propertyName)', '\(op.op.token)', \(input(0))")

       case is BeginIf:
           w.emit("BeginIf \(input(0))")
           w.increaseIndentionLevel()

        case let op as BeginWhile:
            w.emit("BeginWhile \(input(0)), '\(op.comparator.token)', \(input(1))")
            w.increaseIndentionLevel()

        case is EndWhile:
            w.decreaseIndentionLevel()
            w.emit("EndWhile")

        case let op as BeginDoWhile:
            w.emit("BeginDoWhile \(input(0)), '\(op.comparator.token)', \(input(1))")
            w.increaseIndentionLevel()

        case is EndDoWhile:
            w.decreaseIndentionLevel()
            w.emit("EndDoWhile")

        case let op as BeginFor:
            w.emit("BeginFor \(input(0)), '\(op.comparator.token)', \(input(1)), '\(op.op.token)', \(input(2)) -> \(instr.innerOutput)")
            w.increaseIndentionLevel()

        case is EndFor:
            w.decreaseIndentionLevel()
            w.emit("EndFor")

        case is BeginForIn:
            w.emit("BeginForIn \(input(0)) -> \(instr.innerOutput)")
            w.increaseIndentionLevel()

        case is EndForIn:
            w.decreaseIndentionLevel()
            w.emit("EndForIn")

        case is BeginForOf:
            w.emit("BeginForOf \(input(0)) -> \(instr.innerOutput)")
            w.increaseIndentionLevel()

        case let op as BeginForOfWithDestruct:
            let outputs = instr.innerOutputs.map({ $0.identifier })
            w.emit(" BeginForOf \(input(0)) -> [\(liftArrayPattern(indices: op.indices, outputs: outputs, hasRestElement: op.hasRestElement))]")
            w.increaseIndentionLevel()

        case is EndForOf:
            w.decreaseIndentionLevel()
            w.emit("EndForOf")

        case is LoopBreak,
             is SwitchBreak:
            w.emit("Break")

        case is Continue:
            w.emit("Continue")

        case is BeginTry:
            w.emit("BeginTry")
            w.increaseIndentionLevel()

        case is BeginCatch:
            w.decreaseIndentionLevel()
            w.emit("BeginCatch -> \(instr.innerOutput)")
            w.increaseIndentionLevel()

        case is BeginFinally:
            w.decreaseIndentionLevel()
            w.emit("BeginFinally")
            w.increaseIndentionLevel()

        case is EndTryCatch:
            w.decreaseIndentionLevel()
            w.emit("EndTryCatch")

        case is ThrowException:
            w.emit("ThrowException \(input(0))")

        case is BeginCodeString:
            w.emit("\(instr.output) <- BeginCodeString")
            w.increaseIndentionLevel()

        case is EndCodeString:
            w.decreaseIndentionLevel()
            w.emit("EndCodeString")

        case is BeginBlockStatement:
            w.emit("BeginBlockStatement")
            w.increaseIndentionLevel()

        case is EndBlockStatement:
            w.decreaseIndentionLevel()
            w.emit("EndBlockStatement")

        case is Print:
            w.emit("Print \(input(0))")

        default:
            fatalError("Unhandled Operation: \(type(of: instr.op))")
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

            var typeUpdates: [[(Variable, Type)]] = []
            if options.contains(.dumpTypes) {
                typeUpdates = program.types.indexedByInstruction(for: program)
            }

            lift(instr, with: &w)

            if options.contains(.dumpTypes) {
                for (v, t) in typeUpdates[instr.index] {
                    w.emitComment("\(v) = \(t.abbreviated)")
                }
            }
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
}

