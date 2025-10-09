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

/// Type inference for JavaScript variables.
public struct JSTyper: Analyzer {
    // TODO: possible improvements:
    //  - Add awareness of dead code, such as code after a return or singular operations if
    //    there is already another singular operation in the surrounding block (in which case
    //    only the first singular operation is executed at runtime)

    // The environment model from which to obtain various pieces of type information.
    private let environment: JavaScriptEnvironment

    // The current state
    private var state = AnalyzerState()

    private var defUseAnalyzer = DefUseAnalyzer()

    // Parameter types for subroutines defined in the analyzed program.
    // These are keyed by the index of the start of the subroutine definition.
    private var signatures = [Int: ParameterList]()

    // Tracks the wasm recursive type groups and their contained types.
    private var typeGroups: [[Variable]] = []
    // Tracks the direct and transitive dependencies of each type group index to the respective
    // type group indices.
    private var typeGroupDependencies: [Int:Set<Int>] = [:]
    private var selfReferences: [Variable: [(inout JSTyper, Variable?) -> ()]] = [:]
    private var isWithinTypeGroup = false

    // Tracks the active function definitions and contains the instruction that started the function.
    private var activeFunctionDefinitions = Stack<Instruction>()

    /// This tracks program local object groups of various types (WasmModules, JS Classes and Object literals).
    private var dynamicObjectGroupManager = ObjectGroupManager()

    public class ObjectGroupManager {
        /// The finalized object groups that we can query through the Typer.
        var finalizedObjectGroups = [ObjectGroup]()

        struct SeenWasmVariables {
            var globalImports: [Variable] = []
            var globalDefines: [Variable] = []
            var tableImports: [Variable] = []
            var tableDefines: [Variable] = []
            var tagImports: [Variable] = []
            var tagDefines: [Variable] = []
            var memoryImports: [Variable] = []
            var memoryDefines: [Variable] = []
            // For function imports we also need to discriminate on their signature as we can have multiple different callsites with different Signatures for a single function outside of Wasm.
            var functionImports: [(Variable, Signature)] = []
            var functionDefines: [Variable] = []

            var globals : [Variable] {
                return globalImports + globalDefines
            }

            var tables: [Variable] {
                return tableImports + tableDefines
            }

            var tags: [Variable] {
                return tagImports + tagDefines
            }

            var memories: [Variable] {
                return memoryImports + memoryDefines
            }
        }

        var seenWasmVars = SeenWasmVariables()

        /// These are the different types of program local object groups this typer can track.
        /// TODO(cffsmith): We could also track WasmGlobals here.
        public enum ObjectGroupType: CaseIterable {
            case wasmModule
            case wasmExports
            case objectLiteral
            case jsClass
        }

        public var top: ObjectGroup {
            return activeObjectGroups.top
        }

        private var numObjectGroups: Int {
            return finalizedObjectGroups.count + activeObjectGroups.count
        }

        public var numActiveClasses: Int {
            return activeClasses.count
        }

        public var isEmpty: Bool {
            return numObjectGroups == 0
        }

        /// This stack has different object group types
        var activeObjectGroups = Stack<ObjectGroup>()

        public struct ClassDefinition {
            var output: Variable
            // Tracks the objectGroup describing the class, i.e. signatures and types of static properties / methods.
            var objectGroup: ObjectGroup
            var constructorParameters: ParameterList = []
            let superType: ILType
            let superConstructorType: ILType
        }

        // Stack of active class definitions. As class definitions can be nested, this has to be a stack.
        var activeClasses = Stack<ClassDefinition>()

        public func getGroup(withName name: String) -> ObjectGroup? {
            if let group = activeObjectGroups.elementsStartingAtTop().first(where: {group in group.name == name}) {
                return group
            } else if let cls = activeClasses.elementsStartingAtTop().first(where: {cls in cls.objectGroup.name == name}) {
                return cls.objectGroup
            } else {
                return self.finalizedObjectGroups.first(where: {group in group.name == name})
            }
        }

        /// Finalizes the most recently opened ObjectGroup of this type.
        private func finalize(type: ObjectGroupType) -> ILType {
            let group = activeObjectGroups.pop()
            // Make sure that we don't already have such a named group in our finalizedObjectGroups
            assert(!finalizedObjectGroups.contains(where: { group.name == $0.name }))
            finalizedObjectGroups.append(group)
            let instanceType = group.instanceType
            return instanceType
        }

        public func finalizeClass() -> (ILType, ClassDefinition) {
            let instanceType = finalize(type: .jsClass)
            let classDefinition = activeClasses.pop()
            // This is the ObjectGroup tracking the constructor.
            let group = classDefinition.objectGroup
            // Make sure that we don't already have such a named group in our finalizedObjectGroups
            assert(!finalizedObjectGroups.contains(where: { group.name == $0.name }))
            finalizedObjectGroups.append(group)
            return (instanceType, classDefinition)
        }

        public func finalizeObjectLiteral() -> ILType {
            finalize(type: .objectLiteral)
        }

        public func finalizeWasmModule() -> ILType {
            // Get the instance type of the exports
            let exportsInstanceType = finalize(type: .wasmExports)

            addProperty(propertyName: "exports")
            updatePropertyType(propertyName: "exports", type: exportsInstanceType)

            // Clear the seenWasmVariables
            seenWasmVars = SeenWasmVariables()
            return finalize(type: .wasmModule)
        }

        public func createNewWasmModule() {
            let instanceName = "_fuzz_WasmModule\(numObjectGroups)"

            let instanceType = ILType.object(ofGroup: instanceName, withProperties: ["exports"], withMethods: [])

            let instanceNameExports = "_fuzz_WasmExports\(numObjectGroups)"
            let instanceTypeExports = ILType.object(ofGroup: instanceNameExports, withProperties: [], withMethods: [])

            // This ObjectGroup tracking the Module itself is basically finished as it only has the `.exports` property
            // which we track, the rest is tracked on the ObjectGroup tracking the `.exports` field of this Module.
            // The ObjectGroup tracking the `.exports` field will be further modified to track exported functions and other properties.
            let objectGroupModule = ObjectGroup(name: instanceName, instanceType: instanceType, properties: ["exports": instanceTypeExports], methods: [:])
            activeObjectGroups.push(objectGroupModule)

            let objectGroupModuleExports = ObjectGroup(name: instanceNameExports, instanceType: instanceTypeExports, properties: [:], methods: [:])
            activeObjectGroups.push(objectGroupModuleExports)
        }

        func createNewObjectLiteral() {
            let instanceName = "_fuzz_Object\(numObjectGroups)"
            let instanceType: ILType = .object(ofGroup: instanceName, withProperties: [], withMethods: [])

            // This is the dynamic object group.
            let objectGroup = ObjectGroup(name: instanceName, instanceType: instanceType, properties: [:], methods: [:])
            activeObjectGroups.push(objectGroup)
        }

        func createNewClass(withSuperType superType: ILType, propertyMap: [String: ILType], methodMap: [String: [Signature]], superConstructorType: ILType, forOutput output: Variable) {

            let numGroups = numObjectGroups
            let instanceName = "_fuzz_Class\(numGroups)"

            // This type and the object group will be updated dynamically
            let instanceType: ILType = .object(ofGroup: instanceName, withProperties: Array(superType.properties), withMethods: Array(superType.methods))

            // This is the wip object group.
            let objectGroup = ObjectGroup(name: instanceName, instanceType: instanceType, properties: propertyMap, overloads: methodMap)
            activeObjectGroups.push(objectGroup)

            let classInstanceName = "_fuzz_Constructor\(numGroups)"
            let classObjectGroup = ObjectGroup(name: classInstanceName, instanceType: .object(ofGroup: classInstanceName), properties: [:], overloads: [:])

            let classDefinition = ClassDefinition(output: output, objectGroup: classObjectGroup, superType: superType, superConstructorType: superConstructorType)
            activeClasses.push(classDefinition)
        }

        public func setConstructorParameters(parameters: ParameterList) {
            activeClasses.top.constructorParameters = parameters
        }

        public func addClassStaticProperty(propertyName: String) {
            let classType = activeClasses.top.objectGroup.instanceType
            let newType = ILType.object(ofGroup: classType.group, withProperties: [propertyName]) + classType
            assert(newType != .nothing)
            activeClasses.top.objectGroup.properties[propertyName] = .jsAnything
            activeClasses.top.objectGroup.instanceType = newType
        }

        public func updateClassStaticPropertyType(propertyName: String, type: ILType) {
            assert(activeClasses.top.objectGroup.instanceType.properties.contains(propertyName))
            assert(activeClasses.top.objectGroup.properties.contains(where: {k, v in k == propertyName}))
            activeClasses.top.objectGroup.properties[propertyName] = type
        }

        public func addClassStaticMethod(methodName: String) {
            let classType = activeClasses.top.objectGroup.instanceType
            let newType = ILType.object(ofGroup: classType.group, withMethods: [methodName]) + classType
            assert(newType != .nothing)
            activeClasses.top.objectGroup.instanceType = newType

            activeClasses.top.objectGroup.methods[methodName] = activeClasses.top.objectGroup.methods[methodName] ?? [] + [Signature.forUnknownFunction]
            activeClasses.top.objectGroup.instanceType = newType
        }

        public func updateClassStaticMethodSignature(methodName: String, signature: Signature) {
            assert(activeClasses.top.objectGroup.instanceType.methods.contains(methodName))
            activeClasses.top.objectGroup.methods[methodName]!.append(signature)
        }

        // For all of the functions below the following holds which is why we can check the required context on an instruction.
        //
        // module A {
        //   globalA = ...                                <- goes out of scope.
        // }
        //
        // globalA = loadProperty "wg0" moduleA.exports   <- Source of the global is here now.
        //
        // module B {
        //   functionA = {
        //     WasmGlobalGet input=globalA                <- globalA seems to come from "JS"
        //    }
        // }
        //
        // This works because the definition of the import is always the result of
        // a "getProperty" instruction in JS. In a way it is similar to the TypeGroups.
        // globalA ceases to exist after module A ends, yet we can access it through the getProperty instruction,
        // as such "defined in Wasm" (i.e. requiredContext contains wasm) below means "defined in this module".
        // This is a feature as the module doesn't care as these imports always have to come from JS.

        public func addWasmFunction(withSignature signature: Signature, forDefinition instr: Instruction, forVariable variable: Variable) {
            // The instruction might have multiple outputs, i.e. a DestructObject, which is why we cannot know which output variable the correct one is.

            let haveFunction = seenWasmVars.functionImports.contains(where: {
                $0.0 == variable && $0.1 == signature
            }) || seenWasmVars.functionDefines.contains(variable)

            if !haveFunction {
                if instr.op.requiredContext.inWasm {
                    let methodName = "w\(seenWasmVars.functionDefines.count)"
                    seenWasmVars.functionDefines.append(variable)
                    addMethod(methodName: methodName, of: .wasmExports)
                    updateMethodSignature(methodName: methodName, signature: signature)
                } else {
                    let methodName = "iw\(seenWasmVars.functionImports.count)"
                    seenWasmVars.functionImports.append((variable, signature))
                    addMethod(methodName: methodName, of: .wasmExports)
                    updateMethodSignature(methodName: methodName, signature: signature)
                }
            }
        }

        public func addWasmGlobal(withType type: ILType, forDefinition instr: Instruction, forVariable variable: Variable) {
            // The instruction might have multiple outputs, i.e. a DestructObject, which is why we cannot know which output variable the correct one is.
            // Add this property only if we have not seen it before
            if !seenWasmVars.globals.contains(variable) {
                // Check where this global comes from, i.e. if it is imported or internally defined.
                var propertyName: String
                if instr.op.requiredContext.inWasm {
                    propertyName = "wg\(seenWasmVars.globalDefines.count)"
                    seenWasmVars.globalDefines.append(variable)
                } else {
                    propertyName = "iwg\(seenWasmVars.globalImports.count)"
                    seenWasmVars.globalImports.append(variable)
                }
                addProperty(propertyName: propertyName, withType: type)
            }
        }

        public func addWasmTable(withType type: ILType, forDefinition instr: Instruction, forVariable variable: Variable) {
            // The instruction might have multiple outputs, i.e. a DestructObject, which is why we cannot know which output variable the correct one is.
            // Add this property only if we have not seen it before
            var propertyName: String
            if !seenWasmVars.tables.contains(variable) {
                if instr.op.requiredContext.inWasm {
                    propertyName = "wt\(seenWasmVars.tableDefines.count)"
                    seenWasmVars.tableDefines.append(variable)
                } else {
                    propertyName = "iwt\(seenWasmVars.tableImports.count)"
                    seenWasmVars.tableImports.append(variable)
                }
                addProperty(propertyName: propertyName, withType: type)
            }
        }

        public func addWasmMemory(withType type: ILType, forDefinition instr: Instruction, forVariable variable: Variable) {
            // The instruction might have multiple outputs, i.e. a DestructObject, which is why we cannot know which output variable the correct one is.
            // Add this property only if we have not seen it before
            var propertyName: String
            if !seenWasmVars.memories.contains(variable) {
                if instr.op.requiredContext.inWasm {
                    propertyName = "wm\(seenWasmVars.memoryDefines.count)"
                    seenWasmVars.memoryDefines.append(variable)
                } else {
                    propertyName = "iwm\(seenWasmVars.memoryImports.count)"
                    seenWasmVars.memoryImports.append(variable)
                }
                addProperty(propertyName: propertyName, withType: type)
            }
        }

        public func addWasmTag(withType type: ILType, forDefinition instr: Instruction, forVariable variable: Variable) {
            // The instruction might have multiple outputs, i.e. a DestructObject, which is why we cannot know which output variable the correct one is.
            // Add this property only if we have not seen it before
            var propertyName: String
            if !seenWasmVars.tags.contains(variable) {
                if instr.op.requiredContext.inWasm {
                    propertyName = "wex\(seenWasmVars.tagDefines.count)"
                    seenWasmVars.tagDefines.append(variable)
                } else {
                    propertyName = "iwex\(seenWasmVars.tagImports.count)"
                    seenWasmVars.tagImports.append(variable)
                }
                addProperty(propertyName: propertyName, withType: type)
            }
        }

        public func addMethod(methodName: String, of groupType: ObjectGroupType) {
            let topGroup = activeObjectGroups.top
            let newType = ILType.object(ofGroup: topGroup.name, withMethods: [methodName]) + topGroup.instanceType
            assert(newType != .nothing)
            activeObjectGroups.top.instanceType = newType
            activeObjectGroups.top.methods[methodName] = []
        }

        public func updateMethodSignature(methodName: String, signature: Signature) {
            assert(activeObjectGroups.top.instanceType.methods.contains(methodName))
            activeObjectGroups.top.methods[methodName]!.append(signature)
        }

        public func addProperty(propertyName: String, withType type: ILType) {
            addProperty(propertyName: propertyName)
            updatePropertyType(propertyName: propertyName, type: type)
        }

        public func addProperty(propertyName: String) {
            let topGroup = activeObjectGroups.top
            let newType = ILType.object(ofGroup: topGroup.name, withProperties: [propertyName]) + topGroup.instanceType
            assert(newType != .nothing)
            activeObjectGroups.top.instanceType = newType
        }

        public func updatePropertyType(propertyName: String, type: ILType) {
            let topGroup = activeObjectGroups.top
            assert(topGroup.instanceType.properties.contains(propertyName))
            activeObjectGroups.top.properties[propertyName] = type
        }
    }

    // A stack for active for loops containing the types of the loop variables.
    private var activeForLoopVariableTypes = Stack<[ILType]>()

    // The index of the last instruction that was processed. Just used for debug assertions.
    private var indexOfLastInstruction = -1

    init(for environ: JavaScriptEnvironment) {
        self.environment = environ
    }

    public mutating func reset() {
        indexOfLastInstruction = -1
        state.reset()
        signatures.removeAll()
        typeGroups.removeAll()
        defUseAnalyzer = DefUseAnalyzer()
        isWithinTypeGroup = false
        dynamicObjectGroupManager = ObjectGroupManager()
        assert(activeFunctionDefinitions.isEmpty)
        assert(dynamicObjectGroupManager.isEmpty)
    }

    private mutating func registerWasmMemoryUse(for memory: Variable) {
        let definingInstruction = defUseAnalyzer.definition(of: memory)
        dynamicObjectGroupManager.addWasmMemory(withType: type(of: memory), forDefinition: definingInstruction, forVariable: memory)
    }

    // Array for collecting type changes during instruction execution.
    // Not currently used, but could be used for example to validate the analysis by adding these as comments to programs.
    private var typeChanges = [(Variable, ILType)]()

    mutating func registerTypeGroupDependency(from: Int, to: Int) {
        // If the element type originates from another recursive type group, add a dependency.
        if to != -1 && to != from {
            // Dependencies to other type groups can only refer to previous type groups.
            // This is implicitly guaranteed by the FuzzIL as later type groups' types aren't
            // visible yet.
            assert(to < from)
            if typeGroupDependencies[from, default: []].insert(to).inserted {
                // For simplicity also duplicate all dependencies, so that each set contains
                // all dependent groups including transitive dependencies.
                typeGroupDependencies[from]!.formUnion(typeGroupDependencies[to] ?? [])
            }
        }
    }

    mutating func addSignatureType(def: Variable, signature: WasmSignature, inputs: ArraySlice<Variable>) {
        var inputs = inputs.makeIterator()
        let tgIndex = isWithinTypeGroup ? typeGroups.count - 1 : -1

        // Temporary variable to use by the resolveType capture. It would be nicer to use
        // higher-order functions for this but resolveType has to be a mutating func which doesn't
        // seem to work well with escaping functions.
        var isParameter = true
        let resolveType = { (i: Int, paramType: ILType) in
            if paramType.requiredInputCount() == 0 {
                return paramType
            }
            assert(paramType.Is(.wasmRef(.Index(), nullability: true)))
            let typeDef = inputs.next()!
            let elementDesc = type(of: typeDef).wasmTypeDefinition!.description!
            if elementDesc == .selfReference {
                // Register a resolver callback. See `addArrayType` for details.
                if isParameter {
                    selfReferences[typeDef, default: []].append({typer, replacement in
                        let desc = typer.type(of: def).wasmTypeDefinition!.description as! WasmSignatureTypeDescription
                        var params = desc.signature.parameterTypes
                        params[i] = typer.type(of: replacement ?? def)
                        desc.signature = params => desc.signature.outputTypes
                    })
                } else {
                    selfReferences[typeDef, default: []].append({typer, replacement in
                        let desc = typer.type(of: def).wasmTypeDefinition!.description as! WasmSignatureTypeDescription
                        var outputTypes = desc.signature.outputTypes
                        let nullability = outputTypes[i].wasmReferenceType!.nullability
                        outputTypes[i] = typer.type(of: replacement ?? def).wasmTypeDefinition!.getReferenceTypeTo(nullability: nullability)
                        desc.signature = desc.signature.parameterTypes => outputTypes
                    })
                }

            }
            registerTypeGroupDependency(from: tgIndex, to: elementDesc.typeGroupIndex)
            return type(of: typeDef).wasmTypeDefinition!
                .getReferenceTypeTo(nullability: paramType.wasmReferenceType!.nullability)
        }

        let resolvedParameterTypes = signature.parameterTypes.enumerated().map(resolveType)
        isParameter = false // TODO(mliedtke): Is there a nicer way to capture this?
        let resolvedOutputTypes = signature.outputTypes.enumerated().map(resolveType)
        set(def, .wasmTypeDef(description: WasmSignatureTypeDescription(signature: resolvedParameterTypes => resolvedOutputTypes, typeGroupIndex: tgIndex)))
        if isWithinTypeGroup {
            typeGroups[typeGroups.count - 1].append(def)
        }
    }

    mutating func addArrayType(def: Variable, elementType: ILType, mutability: Bool, elementRef: Variable? = nil) {
        let tgIndex = isWithinTypeGroup ? typeGroups.count - 1 : -1
        let resolvedElementType: ILType
        if let elementRef = elementRef {
            let elementNullability = elementType.wasmReferenceType!.nullability
            let typeDefType = type(of: elementRef)
            guard let elementDesc = typeDefType.wasmTypeDefinition?.description  else {
                // TODO(mliedtke): Investigate. The `typeDefType` should be `.wasmTypeDef`.
                // The `elementType` should be `.wasmRef(.Index)`?
                let missesDef = typeDefType.wasmTypeDefinition != nil
                fatalError("Missing \(missesDef ? "definition" : "description") for type definition type \(typeDefType), elementType = \(elementType)")
            }
            if elementDesc == .selfReference {
                // Register a "resolver" callback that does one of the two:
                // 1) If replacement == nil, it replaces the .selfReference with the "outer" array
                //    type (`def`), so the elementType's ILType is now the same as the outer
                //    ILType.
                // 2) If replacement != nil, it replaces the .selfReference with the replacement
                //    for which we now have a "resolved" ILType that we can embed into the
                //    elementType. This can lead to cyclic / recursive ILTypes as well.
                // This callback will be called either when using a WasmResolveForwardReferenceType
                // operation (triggering case 2) or when reaching the wasmEndTypeGroup of the
                // current type group (case 1).
                selfReferences[elementRef, default: []].append({typer, replacement in
                    (typer.type(of: def).wasmTypeDefinition!.description as! WasmArrayTypeDescription).elementType
                        = typer.type(of: replacement ?? def).wasmTypeDefinition!.getReferenceTypeTo(nullability: elementNullability)
                })
            }
            resolvedElementType = type(of: elementRef).wasmTypeDefinition!.getReferenceTypeTo(nullability: elementNullability)
            registerTypeGroupDependency(from: tgIndex, to: elementDesc.typeGroupIndex)
        } else {
            resolvedElementType = elementType
        }
        set(def, .wasmTypeDef(description: WasmArrayTypeDescription(
            elementType: resolvedElementType,
            mutability: mutability,
            typeGroupIndex: tgIndex)))
        if isWithinTypeGroup {
            typeGroups[typeGroups.count - 1].append(def)
        }
    }

    mutating func addStructType(def: Variable, fieldsWithRefs: [(WasmStructTypeDescription.Field, Variable?)]) {
        let tgIndex = isWithinTypeGroup ? typeGroups.count - 1 : -1
        let resolvedFields = fieldsWithRefs.enumerated().map { (fieldIndex, fieldWithInput) in
            let (field, fieldTypeRef) = fieldWithInput
            if let fieldTypeRef {
                let fieldNullability = field.type.wasmReferenceType!.nullability
                let typeDefType = type(of: fieldTypeRef)
                guard let fieldTypeDesc = typeDefType.wasmTypeDefinition?.description  else {
                    // TODO(mliedtke): Investigate.
                    let missesDef = typeDefType.wasmTypeDefinition != nil
                    fatalError("Missing \(missesDef ? "definition" : "description") for type definition type \(typeDefType), field.type = \(field.type)")
                }
                if fieldTypeDesc == .selfReference {
                    // Register a resolver callback. See `addArrayType` for details.
                    selfReferences[fieldTypeRef, default: []].append({typer, replacement in
                        (typer.type(of: def).wasmTypeDefinition!.description! as! WasmStructTypeDescription).fields[fieldIndex].type =
                            typer.type(of: replacement ?? def).wasmTypeDefinition!.getReferenceTypeTo(nullability: fieldNullability)
                    })
                }

                registerTypeGroupDependency(from: tgIndex, to: fieldTypeDesc.typeGroupIndex)

                return WasmStructTypeDescription.Field(
                    type: type(of: fieldTypeRef).wasmTypeDefinition!.getReferenceTypeTo(nullability: fieldNullability),
                    mutability: field.mutability)
            } else {
                return field
            }
        }

        set(def, .wasmTypeDef(description: WasmStructTypeDescription(
            fields: resolvedFields, typeGroupIndex: tgIndex)))
        if (isWithinTypeGroup) {
            typeGroups[typeGroups.count - 1].append(def)
        }
    }

    func getTypeGroup(_ index: Int) -> [Variable] {
        return typeGroups[index]
    }

    func getTypeGroupCount() -> Int {
        return typeGroups.count
    }

    func getTypeGroupDependencies(typeGroupIndex: Int) -> Set<Int> {
        return typeGroupDependencies[typeGroupIndex] ?? []
    }

    mutating func startTypeGroup() {
        assert(!isWithinTypeGroup)
        assert(selfReferences.count == 0)
        isWithinTypeGroup = true
        typeGroups.append([])
    }

    mutating func finishTypeGroup() {
        assert(isWithinTypeGroup)
        for (_, resolvers) in selfReferences {
            for resolve in resolvers {
                resolve(&self, nil)
            }
        }
        selfReferences.removeAll()

        isWithinTypeGroup = false
    }

    mutating func setReferenceType(of: Variable, typeDef: Variable, nullability: Bool) {
        setType(of: of, to: type(of: typeDef).wasmTypeDefinition!.getReferenceTypeTo(nullability: nullability))
    }

    // Returns the type description for the provided variable which has to be either a type
    // definition or an instance (wasm reference) of the wasm type.
    func getTypeDescription(of variable: Variable) -> WasmTypeDescription {
        let varType = type(of: variable)
        if case .Index(let desc) = varType.wasmReferenceType?.kind {
            return desc.get()!
        }
        return varType.wasmTypeDefinition!.description!
    }

    // Helper function to type a "regular" wasm begin block (block, if, try).
    mutating func wasmTypeBeginBlock(_ instr: Instruction, _ signature: WasmSignature) {
        setType(of: instr.innerOutputs.first!, to: .label(signature.outputTypes))
        for (innerOutput, paramType) in zip(instr.innerOutputs.dropFirst(), signature.parameterTypes) {
            setType(of: innerOutput, to: paramType)
        }
    }

    // Helper function to type a "regular" wasm end block.
    mutating func wasmTypeEndBlock(_ instr: Instruction, _ outputTypes: [ILType]) {
        for (output, outputType) in zip(instr.outputs, outputTypes) {
            setType(of: output, to: outputType)
        }
    }

    /// Analyze the given instruction, thus updating type information.
    public mutating func analyze(_ instr: Instruction) {
        assert(instr.index == indexOfLastInstruction + 1)
        indexOfLastInstruction += 1
        defUseAnalyzer.analyze(instr)

        // This typer is currently "Outside" of the wasm module, we just type
        // the instructions here such that we can set the type of the module at
        // the end. Figure out how we can set the correct type at the end?
        if (instr.op is WasmOperation) {
            switch instr.op.opcode {
            case .consti64(_):
                setType(of: instr.output, to: .wasmi64)
            case .consti32(_):
                setType(of: instr.output, to: .wasmi32)
            case .constf64(_):
                setType(of: instr.output, to: .wasmf64)
            case .constf32(_):
                setType(of: instr.output, to: .wasmf32)
            case .wasmi32CompareOp(_),
                 .wasmi64CompareOp(_),
                 .wasmf32CompareOp(_),
                 .wasmf64CompareOp(_):
                setType(of: instr.output, to: .wasmi32)
            case .wasmi32EqualZero(_),
                 .wasmi64EqualZero(_):
                setType(of: instr.output, to: .wasmi32)
            case .wasmi32BinOp(_),
                 .wasmi32UnOp(_),
                 .wasmWrapi64Toi32(_),
                 .wasmTruncatef32Toi32(_),
                 .wasmTruncatef64Toi32(_),
                 .wasmReinterpretf32Asi32(_),
                 .wasmSignExtend8Intoi32(_),
                 .wasmSignExtend16Intoi32(_),
                 .wasmTruncateSatf32Toi32(_),
                 .wasmTruncateSatf64Toi32(_):
                setType(of: instr.output, to: .wasmi32)
            case .wasmi64BinOp(_),
                 .wasmi64UnOp(_),
                 .wasmExtendi32Toi64(_),
                 .wasmTruncatef32Toi64(_),
                 .wasmTruncatef64Toi64(_),
                 .wasmReinterpretf64Asi64(_),
                 .wasmSignExtend8Intoi64(_),
                 .wasmSignExtend16Intoi64(_),
                 .wasmSignExtend32Intoi64(_),
                 .wasmTruncateSatf32Toi64(_),
                 .wasmTruncateSatf64Toi64(_):
                setType(of: instr.output, to: .wasmi64)
            case .wasmf32BinOp(_),
                 .wasmf32UnOp(_),
                 .wasmConverti32Tof32(_),
                 .wasmConverti64Tof32(_),
                 .wasmDemotef64Tof32(_),
                 .wasmReinterpreti32Asf32(_):
                setType(of: instr.output, to: .wasmf32)
            case .wasmf64BinOp(_),
                 .wasmf64UnOp(_),
                 .wasmConverti32Tof64(_),
                 .wasmConverti64Tof64(_),
                 .wasmPromotef32Tof64(_),
                 .wasmReinterpreti64Asf64(_):
                setType(of: instr.output, to: .wasmf64)
            case .constSimd128(_),
                 .wasmSimd128Compare(_),
                 .wasmSimd128IntegerBinOp(_),
                 .wasmSimd128IntegerTernaryOp(_),
                 .wasmSimd128FloatUnOp(_),
                 .wasmSimd128FloatBinOp(_),
                 .wasmSimd128FloatTernaryOp(_),
                 .wasmSimdSplat(_),
                 .wasmSimdLoad(_),
                 .wasmSimdLoadLane(_),
                 .wasmSimdReplaceLane(_):
                setType(of: instr.output, to: .wasmSimd128)
            case .wasmSimd128IntegerUnOp(let op):
                var outputType: ILType = .wasmSimd128
                switch op.unOpKind {
                case .all_true, .bitmask:
                    // Tests and bitmasks produce a boolean i32 result
                    outputType = .wasmi32
                default:
                    break
                }
                setType(of: instr.output, to: outputType)
            case .wasmSimdExtractLane(let op):
                setType(of: instr.output, to: op.kind.laneType())
            case .wasmDefineGlobal(let op):
                let type = ILType.object(ofGroup: "WasmGlobal", withProperties: ["value"], withMethods: ["valueOf"], withWasmType: WasmGlobalType(valueType: op.wasmGlobal.toType(), isMutable: op.isMutable))
                dynamicObjectGroupManager.addWasmGlobal(withType: type, forDefinition: instr, forVariable: instr.output)
                setType(of: instr.output, to: type)
            case .wasmDefineTable(let op):
                setType(of: instr.output, to: .wasmTable(wasmTableType: WasmTableType(elementType: op.elementType, limits: op.limits, isTable64: op.isTable64, knownEntries: op.definedEntries)))
                dynamicObjectGroupManager.addWasmTable(withType: type(of: instr.output), forDefinition: instr, forVariable: instr.output)
                // Also re-export all functions that we now import through the activeElementSection
                for (idx, entry) in op.definedEntries.enumerated() {
                    let definingInstruction = defUseAnalyzer.definition(of: instr.input(idx))
                    // TODO(cffsmith): Once we change the way we track signatures, we should also store the JS Signature here if we have one. The table might contain JS functions but we lose that signature in the entries. Which is why we convert back into JS Signatures here.
                    let jsSignature = ProgramBuilder.convertWasmSignatureToJsSignature(entry.signature)
                    dynamicObjectGroupManager.addWasmFunction(withSignature: jsSignature, forDefinition: definingInstruction, forVariable: instr.input(idx))
                }
            case .wasmDefineElementSegment(let op):
                setType(of: instr.output, to: .wasmElementSegment(segmentLength: Int(op.size)))
            case .wasmDropElementSegment(_):
                type(of: instr.input(0)).wasmElementSegmentType!.markAsDropped()
            case .wasmTableInit(_),
                 .wasmTableCopy(_):
                let definingInstruction = defUseAnalyzer.definition(of: instr.input(0))
                dynamicObjectGroupManager.addWasmTable(withType: type(of: instr.input(0)), forDefinition: definingInstruction, forVariable: instr.input(0))
                // Ignore changed function signatures - it is too hard to reason about them statically.
            case .wasmDefineMemory(let op):
                setType(of: instr.output, to: op.wasmMemory)
                registerWasmMemoryUse(for: instr.output)
            case .wasmDefineDataSegment(let op):
                setType(of: instr.output, to: .wasmDataSegment(segmentLength: op.segment.count))
            case .wasmDropDataSegment(_):
                type(of: instr.input(0)).wasmDataSegmentType!.markAsDropped()
            case .wasmDefineTag(let op):
                setType(of: instr.output, to: .object(ofGroup: "WasmTag", withWasmType: WasmTagType(op.parameterTypes)))
                dynamicObjectGroupManager.addWasmTag(withType: type(of: instr.output), forDefinition: instr, forVariable: instr.output)
            case .wasmThrow(_):
                let definingInstruction = defUseAnalyzer.definition(of: instr.input(0))
                dynamicObjectGroupManager.addWasmTag(withType: type(of: instr.input(0)), forDefinition: definingInstruction, forVariable: instr.input(0))
            case .wasmLoadGlobal(let op):
                let definingInstruction = defUseAnalyzer.definition(of: instr.input(0))
                dynamicObjectGroupManager.addWasmGlobal(withType: type(of: instr.input(0)), forDefinition: definingInstruction, forVariable: instr.input(0))
                setType(of: instr.output, to: op.globalType)
            case .wasmStoreGlobal(_):
                let definingInstruction = defUseAnalyzer.definition(of: instr.input(0))
                dynamicObjectGroupManager.addWasmGlobal(withType: type(of: instr.input(0)), forDefinition: definingInstruction, forVariable: instr.input(0))
            case .wasmTableGet(let op):
                let definingInstruction = defUseAnalyzer.definition(of: instr.input(0))
                dynamicObjectGroupManager.addWasmTable(withType: type(of: instr.input(0)), forDefinition: definingInstruction, forVariable: instr.input(0))
                setType(of: instr.output, to: op.tableType.elementType)
            case .wasmTableSet(_):
                let definingInstruction = defUseAnalyzer.definition(of: instr.input(0))
                dynamicObjectGroupManager.addWasmTable(withType: type(of: instr.input(0)), forDefinition: definingInstruction, forVariable: instr.input(0))
            case .wasmTableSize(_),
                 .wasmTableGrow(_):
                let isTable64 = type(of: instr.input(0)).wasmTableType?.isTable64 ?? false
                let definingInstruction = defUseAnalyzer.definition(of: instr.input(0))
                dynamicObjectGroupManager.addWasmTable(withType: type(of: instr.input(0)), forDefinition: definingInstruction, forVariable: instr.input(0))
                setType(of: instr.output, to: isTable64 ? .wasmi64 : .wasmi32)
            case .wasmMemoryStore(_):
                registerWasmMemoryUse(for: instr.input(0))
            case .wasmMemoryLoad(let op):
                registerWasmMemoryUse(for: instr.input(0))
                setType(of: instr.output, to: op.loadType.numberType())
            case .wasmAtomicLoad(let op):
                registerWasmMemoryUse(for: instr.input(0))
                setType(of: instr.output, to: op.loadType.numberType())
            case .wasmAtomicStore(_):
                registerWasmMemoryUse(for: instr.input(0))
            case .wasmAtomicRMW(let op):
                registerWasmMemoryUse(for: instr.input(0))
                setType(of: instr.output, to: op.op.type())
            case .wasmAtomicCmpxchg(let op):
                registerWasmMemoryUse(for: instr.input(0))
                setType(of: instr.output, to: op.op.type())
            case .wasmMemorySize(_),
                 .wasmMemoryGrow(_):
                let isMemory64 = type(of: instr.input(0)).wasmMemoryType?.isMemory64 ?? false
                registerWasmMemoryUse(for: instr.input(0))
                setType(of: instr.output, to: isMemory64 ? .wasmi64 : .wasmi32)
            case .wasmJsCall(let op):
                let sigOutputTypes = op.functionSignature.outputTypes
                assert(sigOutputTypes.count < 2, "multi-return js calls are not supported")
                if !sigOutputTypes.isEmpty {
                    setType(of: instr.output, to: sigOutputTypes[0])
                }
                let definingInstruction = defUseAnalyzer.definition(of: instr.input(0))
                // Here we query the typer for the signature of the instruction as that is the correct "JS" Signature instead of taking the call-site specific converted wasm signature.
                dynamicObjectGroupManager.addWasmFunction(withSignature: type(of: instr.input(0)).signature ?? Signature.forUnknownFunction, forDefinition: definingInstruction, forVariable: instr.input(0))
            case .beginWasmFunction(let op):
                wasmTypeBeginBlock(instr, op.signature)
            case .endWasmFunction(let op):
                setType(of: instr.output, to: .wasmFunctionDef(op.signature))
                dynamicObjectGroupManager.addWasmFunction(withSignature: ProgramBuilder.convertWasmSignatureToJsSignature(op.signature), forDefinition: instr, forVariable: instr.output)
            case .wasmSelect(_):
                setType(of: instr.output, to: type(of: instr.input(0)))
            case .wasmBeginBlock(let op):
                wasmTypeBeginBlock(instr, op.signature)
            case .wasmEndBlock(let op):
                wasmTypeEndBlock(instr, op.outputTypes)
            case .wasmBeginIf(let op):
                wasmTypeBeginBlock(instr, op.signature)
            case .wasmBeginElse(let op):
                // The else block is both end and begin block.
                wasmTypeEndBlock(instr, op.signature.outputTypes)
                wasmTypeBeginBlock(instr, op.signature)
            case .wasmEndIf(let op):
                wasmTypeEndBlock(instr, op.outputTypes)
            case .wasmBeginLoop(let op):
                // Note that different to all other blocks the loop's label parameters are the input types
                // of the block, not the result types (because a branch to a loop label jumps to the
                // beginning of the loop block instead of the end.)
                setType(of: instr.innerOutputs.first!, to: .label(op.signature.parameterTypes))
                for (innerOutput, paramType) in zip(instr.innerOutputs.dropFirst(), op.signature.parameterTypes) {
                    setType(of: innerOutput, to: paramType)
                }
            case .wasmEndLoop(let op):
                wasmTypeEndBlock(instr, op.outputTypes)
            case .wasmBeginTryTable(let op):
                wasmTypeBeginBlock(instr, op.signature)
                instr.inputs.forEach { input in
                    if type(of: input).isWasmTagType {
                        let definingInstruction = defUseAnalyzer.definition(of: input)
                        dynamicObjectGroupManager.addWasmTag(withType: type(of: input), forDefinition: definingInstruction, forVariable: input)
                    }
                }
            case .wasmEndTryTable(let op):
                wasmTypeEndBlock(instr, op.outputTypes)
            case .wasmBeginTry(let op):
                wasmTypeBeginBlock(instr, op.signature)
            case .wasmBeginCatchAll(let op):
                setType(of: instr.innerOutputs.first!, to: .label(op.inputTypes))
            case .wasmBeginCatch(let op):
                let tagType = ILType.label(op.signature.outputTypes)
                setType(of: instr.innerOutput(0), to: tagType)
                let definingInstruction = defUseAnalyzer.definition(of: instr.input(0))
                dynamicObjectGroupManager.addWasmTag(withType: type(of: instr.input(0)), forDefinition: definingInstruction, forVariable: instr.input(0))
                setType(of: instr.innerOutput(1), to: .exceptionLabel)
                for (innerOutput, paramType) in zip(instr.innerOutputs.dropFirst(2), op.signature.parameterTypes) {
                    setType(of: innerOutput, to: paramType)
                }
                for (output, outputType) in zip(instr.outputs, op.signature.outputTypes) {
                    setType(of: output, to: outputType)
                }
            case .wasmEndTry(let op):
                wasmTypeEndBlock(instr, op.outputTypes)
            case .wasmBeginTryDelegate(let op):
                wasmTypeBeginBlock(instr, op.signature)
            case .wasmEndTryDelegate(let op):
                wasmTypeEndBlock(instr, op.outputTypes)
            case .wasmCallDirect(let op):
                for (output, outputType) in zip(instr.outputs, op.signature.outputTypes) {
                    setType(of: output, to: outputType)
                }
                // We don't need to update the DynamicObjectGroupManager, as all functions that can be called here are .wasmFunctionDef types, this means we have already added them when we saw the EndWasmFunction instruction.
            case .wasmCallIndirect(let op):
                for (output, outputType) in zip(instr.outputs, op.signature.outputTypes) {
                    setType(of: output, to: outputType)
                }
                // Functions that can be called through a table are also already added by the wasmDefineTable instruction.
                // No need to analyze this and add them to the DynamicObjectGroupManager.
            case .wasmArrayNewFixed(_),
                 .wasmArrayNewDefault(_):
                setReferenceType(of: instr.output, typeDef: instr.input(0), nullability: false)
            case .wasmArrayLen(_):
                setType(of: instr.output, to: .wasmi32)
            case .wasmArrayGet(_):
                let typeDesc = getTypeDescription(of: instr.input(0)) as! WasmArrayTypeDescription
                setType(of: instr.output, to: typeDesc.elementType.unpacked())
            case .wasmArraySet(_):
                break
            case .wasmStructNewDefault(_):
                setReferenceType(of: instr.output, typeDef: instr.input(0), nullability: false)
            case .wasmStructGet(let op):
                let typeDesc = getTypeDescription(of: instr.input(0)) as! WasmStructTypeDescription
                setType(of: instr.output, to: typeDesc.fields[op.fieldIndex].type.unpacked())
            case .wasmStructSet(_):
                break;
            case .wasmRefNull(let op):
                if instr.hasInputs {
                    setReferenceType(of: instr.output, typeDef: instr.input(0), nullability: true)
                } else {
                    setType(of: instr.output, to: op.type!)
                }
            case .wasmRefIsNull(_):
                setType(of: instr.output, to: .wasmi32)
            case .wasmRefI31(_):
                setType(of: instr.output, to: .wasmRefI31)
            case .wasmI31Get(_):
                setType(of: instr.output, to: .wasmi32)
            case .wasmAnyConvertExtern(_):
                // any.convert_extern forwards the nullability bit from the input.
                let null = type(of: instr.input(0)).wasmReferenceType!.nullability
                setType(of: instr.output, to: .wasmRef(.Abstract(.WasmAny), nullability: null))
            case .wasmExternConvertAny(_):
                // extern.convert_any forwards the nullability bit from the input.
                let null = type(of: instr.input(0)).wasmReferenceType!.nullability
                setType(of: instr.output, to: .wasmRef(.Abstract(.WasmExtern), nullability: null))
            default:
                if instr.numInnerOutputs + instr.numOutputs != 0 {
                    fatalError("Missing typing of outputs for \(instr.op.opcode)")
                }
            }
        }

        // Reset type changes array before instruction execution.
        typeChanges = []

        processTypeChangesBeforeScopeChanges(instr)

        processScopeChanges(instr)

        processTypeChangesAfterScopeChanges(instr)

        switch instr.op.opcode {
        case .beginWasmModule(_):
            dynamicObjectGroupManager.createNewWasmModule()
        case .endWasmModule(_):
            let instanceType = dynamicObjectGroupManager.finalizeWasmModule()
            setType(of: instr.output, to: instanceType)
        default:
            break
        }

        // Sanity checking: every output variable must now have a type or the Instruction is a Nop (which is why the output will not have a type then).
        assert(instr.allOutputs.allSatisfy(state.hasType) || instr.isNop)
        // No JS output should be .nothing
        assert(instr.allOutputs.allSatisfy { !type(of: $0).Is(.nothing) })

        // More sanity checking: the outputs of guarded operation should be typed as .jsAnything.
        if let op = instr.op as? GuardableOperation, op.isGuarded {
            assert(instr.allOutputs.allSatisfy({ type(of: $0).Is(.jsAnything) }))
        }
    }

    /// Returns the type of the 'super' binding at the current position
    public func currentSuperType() -> ILType {
        // Access to |super| is also allowed in e.g. object methods, but there we can't know the super type.
        if dynamicObjectGroupManager.numActiveClasses > 0 {
            return dynamicObjectGroupManager.activeClasses.top.superType
        } else {
            return .jsAnything
        }
    }

    /// Returns the type of the 'super' binding at the current position
    public func currentSuperConstructorType() -> ILType {
        // Access to |super| is also allowed in e.g. object methods, but there we can't know the super type.
        if dynamicObjectGroupManager.numActiveClasses > 0 {
            // If the superConstructorType is .nothing it means that the current class does not extend anything.
            // In that case, accessing the super constructor type is considered a bug.
            assert(dynamicObjectGroupManager.activeClasses.top.superConstructorType != .nothing)
            return dynamicObjectGroupManager.activeClasses.top.superConstructorType
        } else {
            return .jsAnything
        }
    }

    /// Sets a program-wide signature for the instruction at the given index, which must be the start of a function or method definition.
    public mutating func setParameters(forSubroutineStartingAt index: Int, to parameterTypes: ParameterList) {
        // Currently we expect this to only be used for the next instruction.
        assert(index == indexOfLastInstruction + 1)
        signatures[index] = parameterTypes
    }

    public func inferMethodSignatures(of methodName: String, on objType: ILType) -> [Signature] {
        // Do lookup on our local type information first.
        if let groupName = objType.group {
            if let group = dynamicObjectGroupManager.getGroup(withName: groupName) {
                if let signatures = group.methods[methodName], !signatures.isEmpty, objType.methods.contains(methodName) {
                    return signatures
                } else {
                    // This means the objectGroup doesn't have the function but we did see the objectGroup.
                    return [Signature.forUnknownFunction]
                }
            }
        }

        return environment.signatures(ofMethod: methodName, on: objType)
    }

    /// Attempts to infer the signatures of the overloads of the given method on the given object type.
    public func inferMethodSignatures(of methodName: String, on object: Variable) -> [Signature] {
        return inferMethodSignatures(of: methodName, on: state.type(of: object))
    }

    /// Attempts to infer the type of the given property on the given object type.
    public func inferPropertyType(of propertyName: String, on objType: ILType) -> ILType {
        // Do lookup on our local type information first.
        if let groupName = objType.group {
            if let group = dynamicObjectGroupManager.getGroup(withName: groupName) {
                // Check if we have it in the group and on the actual passed in ILType as it might've been deleted.
                if let type = group.properties[propertyName], objType.properties.contains(propertyName) {
                    return type
                } else if let type = group.methods[propertyName], objType.methods.contains(propertyName) {
                    // If no property is present, look up the name in the methods instead.
                    // Retrieving a method "as a property" results in a variable that is a function
                    // with the method's signature. However, it loses the this-binding:
                    //   let x = {val: 5, method: function() { return this.val; }};
                    //   console.log(x.method()); // prints 5
                    //   let y = x.method;
                    //   console.log(y());        // prints undefined
                    // So this is not 100% precise (parameter types will still be consistent)
                    // but the usage of this inside the function might be "wrong" and the result
                    // type might be off as also shown in the example above.

                    // While a method can have multiple signatures, when converting to an ILType,
                    // we need to pick one, so we just pick the first here (if present).
                    // TODO: Would it be useful to expose all available signatures to the
                    // .function() type? (E.g. a code generator could then randomly pick one.)
                    return .function(type.first)
                } else {
                    // This means the objectGroup doesn't have the property but we did see the objectGroup.
                    return .jsAnything
                }
            }
        }
        return environment.type(ofProperty: propertyName, on: objType)
    }

    /// Attempts to infer the type of the given property on the given object type.
    public func inferPropertyType(of propertyName: String, on object: Variable) -> ILType {
        return inferPropertyType(of: propertyName, on: state.type(of: object))
    }

    /// Attempts to infer the constructed type of the given constructor.
    public func inferConstructedType(of constructor: Variable) -> ILType {
        if let signature = state.type(of: constructor).constructorSignature, signature.outputType != .jsAnything {
            return signature.outputType
        }
        return .object()
    }

    /// Attempts to infer the return value type of the given function.
    private func inferCallResultType(of function: Variable) -> ILType {
        if let signature = state.type(of: function).functionSignature {
            return signature.outputType
        }
        return .jsAnything
    }

    public mutating func setType(of v: Variable, to t: ILType) {
        assert(t != .nothing)
        state.updateType(of: v, to: t)
    }

    public func type(of v: Variable) -> ILType {
        return state.type(of: v)
    }

    /// Attempts to infer the parameter types of the given subroutine definition.
    /// If parameter types have been added for this function, they are returned, otherwise generic parameter types (i.e. .jsAnything parameters) for the parameters specified in the operation are generated.
    private func inferSubroutineParameterList(of op: BeginAnySubroutine, at index: Int) -> ParameterList {
        return signatures[index] ?? ParameterList(numParameters: op.parameters.count, hasRestParam: op.parameters.hasRestParameter)
    }

    // Set type to current state and save type change event
    private mutating func set(_ v: Variable, _ t: ILType) {
        // Record type change if:
        // 1. It is first time we set the type of this variable
        // 2. The type is different from the previous type of that variable
        if !state.hasType(for: v) || state.type(of: v) != t {
            typeChanges.append((v, t))
        }
        setType(of: v, to: t)
    }

    private mutating func processTypeChangesBeforeScopeChanges(_ instr: Instruction) {
        if instr.op is WasmOperation {
            return
        }
        switch instr.op.opcode {
        case .beginWasmModule(_):
            break
        case .endWasmModule(_):
            break
        case .beginPlainFunction(let op):
            // Plain functions can also be used as constructors.
            // The return value type will only be known after fully processing the function definitions.
            set(instr.output, .functionAndConstructor(inferSubroutineParameterList(of: op, at: instr.index) => .jsAnything))
        case .beginArrowFunction(let op as BeginAnyFunction),
             .beginGeneratorFunction(let op as BeginAnyFunction),
             .beginAsyncFunction(let op as BeginAnyFunction),
             .beginAsyncArrowFunction(let op as BeginAnyFunction),
             .beginAsyncGeneratorFunction(let op as BeginAnyFunction):
            set(instr.output, .function(inferSubroutineParameterList(of: op, at: instr.index) => .jsAnything))
        case .beginConstructor(let op):
            set(instr.output, .constructor(inferSubroutineParameterList(of: op, at: instr.index) => .jsAnything))
        case .beginCodeString:
            set(instr.output, .jsString)
        case .beginClassDefinition(let op):
            // The empty object type.
            var superType = ILType.object()
            var superConstructorType: ILType = .nothing
            if op.hasSuperclass {
                superConstructorType = state.type(of: instr.input(0))
                // If the super constructor returns anything other than .object(), then the return type will be
                // the |this| value inside the constructor. However, we don't currently support multiple signatures
                // for the same callable (the call signature and the construct signature), so here in that case
                // we just ignore the super type.
                if let constructorReturnType = superConstructorType.constructorSignature?.outputType, constructorReturnType.Is(.object()) {
                    superType = constructorReturnType
                }
            }
            let propertySuperTypeMap = Dictionary(uniqueKeysWithValues: superType.properties.map { name in
                (name, inferPropertyType(of: name, on: superType))
            })
            let methodSuperTypeMap = Dictionary(uniqueKeysWithValues: superType.methods.map { name in
                (name, inferMethodSignatures(of: name, on: superType))
            })

            dynamicObjectGroupManager.createNewClass(withSuperType: superType, propertyMap: propertySuperTypeMap, methodMap: methodSuperTypeMap, superConstructorType: superConstructorType, forOutput: instr.output)

            set(instr.output, .jsAnything)         // Treat the class variable as unknown until we have fully analyzed the class definition
        case .endClassDefinition:
            let (instanceType, classDefinition) = dynamicObjectGroupManager.finalizeClass()
            set(classDefinition.output, classDefinition.objectGroup.instanceType + .constructor(classDefinition.constructorParameters => instanceType))
        default:
            // Only instructions starting a block with output variables should be handled here.
            assert(instr.numOutputs == 0 || !instr.isBlockStart)
        }
    }

    private mutating func processScopeChanges(_ instr: Instruction) {
        if instr.op is WasmOperation {
            return
        }
        switch instr.op.opcode {
        case .beginObjectLiteral,
             .endObjectLiteral,
             .beginClassDefinition,
             .endClassDefinition,
             .beginClassStaticInitializer,
             .endClassStaticInitializer,
             .beginWasmModule,
             .endWasmModule:
            // Object literals and class definitions don't create any conditional branches, only methods and accessors inside of them. These are handled further below.
            break
        case .beginIf:
            state.startGroupOfConditionallyExecutingBlocks()
            state.enterConditionallyExecutingBlock(typeChanges: &typeChanges)
        case .beginElse:
            state.enterConditionallyExecutingBlock(typeChanges: &typeChanges)
        case .endIf:
            if !state.currentBlockHasAlternativeBlock {
                // This If doesn't have an Else block, so append an empty block representing the state if the If-body is not executed.
                state.enterConditionallyExecutingBlock(typeChanges: &typeChanges)
            }
            state.endGroupOfConditionallyExecutingBlocks(typeChanges: &typeChanges)
        case .beginSwitch:
            state.startSwitch()
        case .beginSwitchCase:
            state.enterSwitchCase(typeChanges: &typeChanges)
        case .beginSwitchDefaultCase:
            state.enterSwitchDefaultCase(typeChanges: &typeChanges)
        case .endSwitchCase:
            break
        case .endSwitch:
            state.endSwitch(typeChanges: &typeChanges)
        case .beginWhileLoopHeader:
            // Loop headers execute unconditionally (at least once).
            break
        case .beginDoWhileLoopBody,
             .beginDoWhileLoopHeader,
             .endDoWhileLoop:
            // Do-While loop headers _and_ bodies execute unconditionally (at least once).
            break
        case .beginForLoopInitializer,
             .beginForLoopCondition:
            // The initializer and the condition of a for-loop's header execute unconditionally.
            break
        case .beginForLoopAfterthought:
            // A for-loop's afterthought and body block execute conditionally.
            state.startGroupOfConditionallyExecutingBlocks()
            // We add an empty block to represent the state when the body and afterthought are never executed.
            state.enterConditionallyExecutingBlock(typeChanges: &typeChanges)
            // Then we add a block to represent the state when they are executed.
            state.enterConditionallyExecutingBlock(typeChanges: &typeChanges)
        case .beginForLoopBody:
            // We keep using the state for the loop afterthought here.
            // TODO, technically we should execute the body before the afterthought block...
            break
        case .endForLoop:
            state.endGroupOfConditionallyExecutingBlocks(typeChanges: &typeChanges)
        case .beginWhileLoopBody,
             .beginForInLoop,
             .beginForOfLoop,
             .beginForOfLoopWithDestruct,
             .beginRepeatLoop,
             .beginCodeString:
            state.startGroupOfConditionallyExecutingBlocks()
            // Push an empty state representing the case when the loop body (or code string) is not executed at all
            state.enterConditionallyExecutingBlock(typeChanges: &typeChanges)
            // Push a new state tracking the types inside the loop
            state.enterConditionallyExecutingBlock(typeChanges: &typeChanges)
        case .endWhileLoop,
             .endForInLoop,
             .endForOfLoop,
             .endRepeatLoop,
             .endCodeString:
            state.endGroupOfConditionallyExecutingBlocks(typeChanges: &typeChanges)
        case .beginObjectLiteralMethod,
             .beginObjectLiteralComputedMethod,
             .beginObjectLiteralGetter,
             .beginObjectLiteralSetter,
             .beginPlainFunction,
             .beginArrowFunction,
             .beginGeneratorFunction,
             .beginAsyncFunction,
             .beginAsyncArrowFunction,
             .beginAsyncGeneratorFunction,
             .beginConstructor,
             .beginClassConstructor,
             .beginClassInstanceMethod,
             .beginClassInstanceComputedMethod,
             .beginClassInstanceGetter,
             .beginClassInstanceSetter,
             .beginClassStaticMethod,
             .beginClassStaticComputedMethod,
             .beginClassStaticGetter,
             .beginClassStaticSetter,
             .beginClassPrivateInstanceMethod,
             .beginClassPrivateStaticMethod:
            activeFunctionDefinitions.push(instr)
            state.startSubroutine()
        case .endObjectLiteralMethod,
             .endObjectLiteralComputedMethod,
             .endObjectLiteralGetter,
             .endObjectLiteralSetter,
             .endPlainFunction,
             .endArrowFunction,
             .endGeneratorFunction,
             .endAsyncFunction,
             .endAsyncArrowFunction,
             .endAsyncGeneratorFunction,
             .endConstructor,
             .endClassConstructor,
             .endClassInstanceMethod,
             .endClassInstanceComputedMethod,
             .endClassInstanceGetter,
             .endClassInstanceSetter,
             .endClassStaticMethod,
             .endClassStaticComputedMethod,
             .endClassStaticGetter,
             .endClassStaticSetter,
             .endClassPrivateInstanceMethod,
             .endClassPrivateStaticMethod:
            //
            // Infer the return type of the subroutine (if necessary for the signature).
            //
            let begin = activeFunctionDefinitions.pop()
            var defaultReturnValueType = ILType.undefined
            if begin.op is BeginConstructor {
                // For a constructor, the default return value is `this`, so use the current type of the
                // `this` object, which is the first inner output of the BeginConstructor operation.
                defaultReturnValueType = type(of: begin.innerOutput(0))
            }

            let returnValueType = state.endSubroutine(typeChanges: &typeChanges, defaultReturnValueType: defaultReturnValueType)

            // Check if the signature is needed, otherwise, we don't need the return value type.
            if begin.numOutputs == 1 {
                let funcType = state.type(of: begin.output)
                // The function variable may have been reassigned to a different function, in which case we may not have a signature anymore.
                if let signature = funcType.signature {
                    switch begin.op.opcode {
                    case .beginGeneratorFunction,
                         .beginAsyncGeneratorFunction:
                        setType(of: begin.output, to: funcType.settingSignature(to: signature.parameters => .jsGenerator))
                    case .beginAsyncFunction,
                         .beginAsyncArrowFunction:
                        setType(of: begin.output, to: funcType.settingSignature(to: signature.parameters => .jsPromise))
                    default:
                        setType(of: begin.output, to: funcType.settingSignature(to: signature.parameters => returnValueType))
                    }
                }
            }

            // TODO(cffsmith): this is probably the wrong place to do this.
            // Update the dynamic object group to correctly reflect the signature of objects of this type.
            switch instr.op.opcode {
            case .endClassInstanceMethod(_):
                assert(begin.op is BeginClassInstanceMethod)
                let beginOp = begin.op as! BeginClassInstanceMethod
                dynamicObjectGroupManager.updateMethodSignature(methodName: beginOp.methodName, signature: inferSubroutineParameterList(of: beginOp, at: begin.index) => returnValueType)
            case .endClassInstanceGetter(_):
                assert(begin.op is BeginClassInstanceGetter)
                let beginOp = begin.op as! BeginClassInstanceGetter
                dynamicObjectGroupManager.updatePropertyType(propertyName: beginOp.propertyName, type: returnValueType)
            case .endClassInstanceSetter(_):
                assert(begin.op is BeginClassInstanceSetter)
                let beginOp = begin.op as! BeginClassInstanceSetter
                dynamicObjectGroupManager.updatePropertyType(propertyName: beginOp.propertyName, type: returnValueType)
            case .endClassStaticGetter(_):
                assert(begin.op is BeginClassStaticGetter)
                let beginOp = begin.op as! BeginClassStaticGetter
                dynamicObjectGroupManager.updateClassStaticPropertyType(propertyName: beginOp.propertyName, type: returnValueType)
            case .endClassStaticMethod(_):
                assert(begin.op is BeginClassStaticMethod)
                let beginOp = begin.op as! BeginClassStaticMethod
                dynamicObjectGroupManager.updateClassStaticMethodSignature(methodName: beginOp.methodName, signature: inferSubroutineParameterList(of: beginOp, at: begin.index) => returnValueType)
            case .endClassStaticSetter(_):
                assert(begin.op is BeginClassStaticSetter)
                let beginOp = begin.op as! BeginClassStaticSetter
                dynamicObjectGroupManager.updateClassStaticPropertyType(propertyName: beginOp.propertyName, type: returnValueType)
            case .endObjectLiteralMethod(_):
                assert(begin.op is BeginObjectLiteralMethod)
                let beginOp = begin.op as! BeginObjectLiteralMethod
                dynamicObjectGroupManager.updateMethodSignature(methodName: beginOp.methodName, signature: inferSubroutineParameterList(of: beginOp, at: begin.index) => returnValueType)
            case .endObjectLiteralGetter(_):
                assert(begin.op is BeginObjectLiteralGetter)
                let beginOp = begin.op as! BeginObjectLiteralGetter
                dynamicObjectGroupManager.updatePropertyType(propertyName: beginOp.propertyName, type: returnValueType)
            case .endObjectLiteralSetter(_):
                assert(begin.op is BeginObjectLiteralSetter)
                let beginOp = begin.op as! BeginObjectLiteralSetter
                dynamicObjectGroupManager.updatePropertyType(propertyName: beginOp.propertyName, type: returnValueType)
            default:
                break
            }


        case .beginTry,
             .beginCatch,
             .beginFinally,
             .endTryCatchFinally:
            break
        case .beginWith,
             .endWith:
            break
        case .beginBlockStatement,
             .endBlockStatement:
            break
        case .wasmBeginTypeGroup,
             .wasmEndTypeGroup:
             break
        default:
            assert(instr.isSimple)
        }
    }

    private mutating func processTypeChangesAfterScopeChanges(_ instr: Instruction) {
        if instr.op is WasmOperation {
            return
        }
        // Helper function to process parameters
        func processParameterDeclarations(_ parameterVariables: ArraySlice<Variable>, parameters: ParameterList) {
            let types = computeParameterTypes(from: parameters)
            assert(types.count == parameterVariables.count)
            for (param, type) in zip(parameterVariables, types) {
                set(param, type)
            }
        }

        func type(ofInput inputIdx: Int) -> ILType {
            return state.type(of: instr.input(inputIdx))
        }

        // When interpreting instructions to determine output types, the general rule is to perform type checks on inputs
        // with the widest, most generic type (e.g. .integer, .bigint, .object), while setting output types to the most
        // specific type possible. In particular, that means that output types should always be fetched from the environment
        // (environment.intType, environment.bigIntType, environment.objectType), to give it a chance to customize the
        // basic types.
        // TODO: fetch all output types from the environment instead of hardcoding them.

        // Helper function to set output type of binary/reassignment operations
        func analyzeBinaryOperation(operator op: BinaryOperator, withInputs inputs: ArraySlice<Variable>) -> ILType {
            switch op {
            case .Add:
                return maybeBigIntOr(.primitive)
            case .Sub,
                 .Mul,
                 .Exp,
                 .Div,
                 .Mod:
                return maybeBigIntOr(.number)
            case .BitAnd,
                 .BitOr,
                 .Xor,
                 .LShift,
                 .RShift,
                 .UnRShift:
                return maybeBigIntOr(.integer)
            case .LogicAnd,
                 .LogicOr,
                 .NullCoalesce:
                return state.type(of: inputs[0]) | state.type(of: inputs[1])
            }
        }

        // Helper function for operations whose results
        // can only be a .bigint if an input to it is
        // a .bigint.
        func maybeBigIntOr(_ t: ILType) -> ILType {
            var outputType = t
            var allInputsAreBigint = true
            for i in 0..<instr.numInputs {
                if type(ofInput: i).MayBe(.bigint) {
                    outputType |= .bigint
                }
                if !type(ofInput: i).Is(.bigint) {
                    allInputsAreBigint = false
                }
            }
            return allInputsAreBigint ? .bigint : outputType
        }

        switch instr.op.opcode {
        case .loadInteger:
            set(instr.output, .integer)

        case .loadBigInt:
            set(instr.output, .bigint)

        case .loadFloat:
            set(instr.output, .float)

        case .loadString(let op):
            if let customName = op.customName {
                if let enumTy = environment.getEnum(ofName: customName) {
                    set(instr.output, enumTy)
                } else {
                    set(instr.output, .namedString(ofName: customName))
                }

            } else {
                set(instr.output, .jsString)
            }

        case .loadBoolean:
            set(instr.output, .boolean)

        case .loadUndefined:
            set(instr.output, .undefined)

        case .loadNull:
            set(instr.output, .undefined)

        case .loadThis:
            set(instr.output, .object())

        case .loadArguments:
            set(instr.output, .jsArguments)

        case .createNamedVariable(let op):
            if op.hasInitialValue {
                set(instr.output, type(ofInput: 0))
            } else if (environment.hasBuiltin(op.variableName)) {
                set(instr.output, environment.type(ofBuiltin: op.variableName))
            } else {
                set(instr.output, .jsAnything)
            }

        case .loadDisposableVariable:
            set(instr.output, type(ofInput: 0))

        case .loadAsyncDisposableVariable:
            set(instr.output, type(ofInput: 0))

        case .createNamedDisposableVariable:
            set(instr.output, type(ofInput: 0))

        case .createNamedAsyncDisposableVariable:
            set(instr.output, type(ofInput: 0))

        case .loadNewTarget:
            set(instr.output, .function() | .undefined)

        case .loadRegExp:
            set(instr.output, .jsRegExp)

        case .beginObjectLiteral:
            dynamicObjectGroupManager.createNewObjectLiteral()

        case .objectLiteralAddProperty(let op):
            dynamicObjectGroupManager.addProperty(propertyName: op.propertyName, withType: type(ofInput: 0))

        case .objectLiteralAddElement,
             .objectLiteralAddComputedProperty,
             .objectLiteralCopyProperties:
            // We cannot currently determine the properties/methods added by these operations.
            break

        case .beginObjectLiteralMethod(let op):
            // The first inner output is the explicit |this| parameter for the constructor
            set(instr.innerOutput(0), dynamicObjectGroupManager.top.instanceType)
            processParameterDeclarations(instr.innerOutputs(1...), parameters: inferSubroutineParameterList(of: op, at: instr.index))
            dynamicObjectGroupManager.addMethod(methodName: op.methodName, of: .objectLiteral)

        case .beginObjectLiteralComputedMethod(let op):
            // The first inner output is the explicit |this| parameter for the constructor
            set(instr.innerOutput(0), dynamicObjectGroupManager.top.instanceType)
            processParameterDeclarations(instr.innerOutputs(1...), parameters: inferSubroutineParameterList(of: op, at: instr.index))

        case .beginObjectLiteralGetter(let op):
            // The first inner output is the explicit |this| parameter for the constructor
            set(instr.innerOutput(0), dynamicObjectGroupManager.top.instanceType)
            assert(instr.numInnerOutputs == 1)
            dynamicObjectGroupManager.addProperty(propertyName: op.propertyName)

        case .beginObjectLiteralSetter(let op):
            // The first inner output is the explicit |this| parameter for the constructor
            set(instr.innerOutput(0), dynamicObjectGroupManager.top.instanceType)
            assert(instr.numInnerOutputs == 2)
            processParameterDeclarations(instr.innerOutputs(1...), parameters: inferSubroutineParameterList(of: op, at: instr.index))
            dynamicObjectGroupManager.addProperty(propertyName: op.propertyName)

        case .endObjectLiteral:
            let instanceType = dynamicObjectGroupManager.finalizeObjectLiteral()
            set(instr.output, instanceType)

        case .beginClassConstructor(let op):
            // The first inner output is the explicit |this| parameter for the constructor
            set(instr.innerOutput(0), dynamicObjectGroupManager.top.instanceType)
            let parameters = inferSubroutineParameterList(of: op, at: instr.index)
            processParameterDeclarations(instr.innerOutputs(1...), parameters: parameters)
            dynamicObjectGroupManager.setConstructorParameters(parameters: parameters)

        case .classAddInstanceProperty(let op):
            dynamicObjectGroupManager.addProperty(propertyName: op.propertyName)
            dynamicObjectGroupManager.updatePropertyType(propertyName: op.propertyName, type: op.hasValue ? type(ofInput: 0) : .jsAnything)

        case .beginClassInstanceMethod(let op):
            // The first inner output is the explicit |this|
            set(instr.innerOutput(0), dynamicObjectGroupManager.top.instanceType)
            processParameterDeclarations(instr.innerOutputs(1...), parameters: inferSubroutineParameterList(of: op, at: instr.index))
            dynamicObjectGroupManager.addMethod(methodName: op.methodName, of: .jsClass)

        case .beginClassInstanceComputedMethod(let op):
            // The first inner output is the explicit |this|
            set(instr.innerOutput(0), dynamicObjectGroupManager.top.instanceType)
            processParameterDeclarations(instr.innerOutputs(1...), parameters: inferSubroutineParameterList(of: op, at: instr.index))

        case .beginClassInstanceGetter(let op):
            // The first inner output is the explicit |this| parameter for the constructor
            set(instr.innerOutput(0), dynamicObjectGroupManager.top.instanceType)
            assert(instr.numInnerOutputs == 1)
            dynamicObjectGroupManager.addProperty(propertyName: op.propertyName)

        case .beginClassInstanceSetter(let op):
            // The first inner output is the explicit |this| parameter for the constructor
            set(instr.innerOutput(0), dynamicObjectGroupManager.top.instanceType)
            assert(instr.numInnerOutputs == 2)
            processParameterDeclarations(instr.innerOutputs(1...), parameters: inferSubroutineParameterList(of: op, at: instr.index))
            dynamicObjectGroupManager.addProperty(propertyName: op.propertyName)

        case .classAddStaticProperty(let op):
            dynamicObjectGroupManager.addClassStaticProperty(propertyName: op.propertyName)

        case .beginClassStaticInitializer:
            // The first inner output is the explicit |this|
            set(instr.innerOutput(0), dynamicObjectGroupManager.activeClasses.top.objectGroup.instanceType)
            assert(instr.numInnerOutputs == 1)

        case .beginClassStaticMethod(let op):
            // The first inner output is the explicit |this|
            set(instr.innerOutput(0), dynamicObjectGroupManager.activeClasses.top.objectGroup.instanceType)
            processParameterDeclarations(instr.innerOutputs(1...), parameters: inferSubroutineParameterList(of: op, at: instr.index))
            dynamicObjectGroupManager.addClassStaticMethod(methodName: op.methodName)

        case .beginClassStaticComputedMethod(let op):
            // The first inner output is the explicit |this|
            set(instr.innerOutput(0), dynamicObjectGroupManager.activeClasses.top.objectGroup.instanceType)
            processParameterDeclarations(instr.innerOutputs(1...), parameters: inferSubroutineParameterList(of: op, at: instr.index))

        case .beginClassStaticGetter(let op):
            // The first inner output is the explicit |this| parameter for the constructor
            set(instr.innerOutput(0), dynamicObjectGroupManager.activeClasses.top.objectGroup.instanceType)
            assert(instr.numInnerOutputs == 1)
            dynamicObjectGroupManager.addClassStaticProperty(propertyName: op.propertyName)

        case .beginClassStaticSetter(let op):
            // The first inner output is the explicit |this| parameter for the constructor
            set(instr.innerOutput(0), dynamicObjectGroupManager.activeClasses.top.objectGroup.instanceType)
            assert(instr.numInnerOutputs == 2)
            processParameterDeclarations(instr.innerOutputs(1...), parameters: inferSubroutineParameterList(of: op, at: instr.index))
            dynamicObjectGroupManager.addClassStaticProperty(propertyName: op.propertyName)

        case .beginClassPrivateInstanceMethod(let op):
            // The first inner output is the explicit |this|
            set(instr.innerOutput(0), dynamicObjectGroupManager.top.instanceType)
            processParameterDeclarations(instr.innerOutputs(1...), parameters: inferSubroutineParameterList(of: op, at: instr.index))

        case .beginClassPrivateStaticMethod(let op):
            // The first inner output is the explicit |this|
            set(instr.innerOutput(0), dynamicObjectGroupManager.activeClasses.top.objectGroup.instanceType)
            processParameterDeclarations(instr.innerOutputs(1...), parameters: inferSubroutineParameterList(of: op, at: instr.index))

        case .createArray,
             .createIntArray,
             .createFloatArray,
             .createArrayWithSpread:
            set(instr.output, .jsArray)

        case .createTemplateString:
            set(instr.output, .jsString)

        case .getProperty(let op):
            set(instr.output, inferPropertyType(of: op.propertyName, on: instr.input(0)))

        case .setProperty(let op):
            set(instr.input(0), type(ofInput: 0).adding(property: op.propertyName))

        case .updateProperty(let op):
            set(instr.input(0), type(ofInput: 0).adding(property: op.propertyName))

        case .configureProperty(let op):
            set(instr.input(0), type(ofInput: 0).adding(property: op.propertyName))

        case .deleteProperty(let op):
            set(instr.input(0), type(ofInput: 0).removing(propertyOrMethod: op.propertyName))
            set(instr.output, .boolean)

            // TODO: An additional analyzer is required to determine the runtime value of the input variable
        case .deleteComputedProperty,
             .deleteElement:
            set(instr.output, .boolean)

            // TODO: An additional analyzer is required to determine the runtime value of the output variable generated from the following operations
            // For now we treat this as .jsAnything
        case .getElement,
             .getComputedProperty,
             .getComputedSuperProperty,
             .callComputedMethod,
             .callComputedMethodWithSpread:
            set(instr.output, .jsAnything)

        case .ternaryOperation:
            let outputType = type(ofInput: 1) | type(ofInput: 2)
            set(instr.output, outputType)

        case .callFunction,
             .callFunctionWithSpread:
            set(instr.output, inferCallResultType(of: instr.input(0)))

        case .construct,
             .constructWithSpread:
            set(instr.output, inferConstructedType(of: instr.input(0)))

        case .callMethod(let op):
            let sigs = inferMethodSignatures(of: op.methodName, on: instr.input(0))
            // op.numInputs - 1 because the signature.numParameters does not include the receiver.
            // TODO: We could make the overload resolution here more accurate
            // by also comparing the types of parameters.
            let sig = sigs.filter({$0.numParameters == op.numInputs - 1}).first ?? chooseUniform(from: sigs)
            set(instr.output, sig.outputType)
        case .callMethodWithSpread(let op):
            let sig = chooseUniform(from: inferMethodSignatures(of: op.methodName, on: instr.input(0)))
            set(instr.output, sig.outputType)

        case .unaryOperation(let op):
            switch op.op {
            case .PreInc,
                 .PreDec,
                 .PostInc,
                 .PostDec:
                set(instr.input(0), maybeBigIntOr(.primitive))
                set(instr.output, maybeBigIntOr(.primitive))
            case .Plus:
                set(instr.output, maybeBigIntOr(.primitive))
            case .Minus:
                set(instr.output, maybeBigIntOr(.primitive))
            case .LogicalNot:
                set(instr.output, .boolean)
            case .BitwiseNot:
                set(instr.output, maybeBigIntOr(.integer))
            }

        case .binaryOperation(let op):
            set(instr.output, analyzeBinaryOperation(operator: op.op, withInputs: instr.inputs))

        case .update(let op):
            set(instr.input(0), analyzeBinaryOperation(operator: op.op, withInputs: instr.inputs))

        case .typeOf:
            set(instr.output, .string)

        case .void:
            set(instr.output, .undefined)

        case .testInstanceOf:
            set(instr.output, .boolean)

        case .testIn:
            set(instr.output, .boolean)

        case .dup:
            set(instr.output, type(ofInput: 0))

        case .reassign:
            set(instr.input(0), type(ofInput: 1))

        case .return(let op):
            if op.hasReturnValue {
                state.updateReturnValueType(to: type(ofInput: 0))
            } else {
                // TODO this isn't correct e.g. for constructors (where the return value would be `this`).
                // To fix that, we could for example add a "placeholder" return value that is replaced by
                // the default return value at the end of the subroutine.
                state.updateReturnValueType(to: .undefined)
            }

        case .destructArray:
            instr.outputs.forEach{set($0, .jsAnything)}

        case .destructArrayAndReassign:
            instr.inputs.dropFirst().forEach{set($0, .jsAnything)}

        case .destructObject(let op):
            for (property, output) in zip(op.properties, instr.outputs) {
                set(output, inferPropertyType(of: property, on: instr.input(0)))
            }
            if op.hasRestElement {
                // TODO: Add the subset of object properties and methods captured by the rest element
                set(instr.outputs.last!, .object())
            }

        case .destructObjectAndReassign(let op):
            for (property, input) in zip(op.properties, instr.inputs.dropFirst()) {
                set(input, inferPropertyType(of: property, on: instr.input(0)))
            }
            if op.hasRestElement {
                // TODO: Add the subset of object properties and methods captured by the rest element
                set(instr.inputs.last!, .object())
            }

        case .compare:
            set(instr.output, .boolean)

        case .await:
            // TODO if input type is known, set to input type and possibly unwrap the Promise
            set(instr.output, .jsAnything)

        case .yield:
            set(instr.output, .jsAnything)

        case .eval:
            if instr.hasOneOutput {
                set(instr.output, .jsAnything)
            }

        case .fixup:
            // As Fixup operations may change the action that they perform at runtime, we cannot statically know the output type.
            if instr.hasOneOutput {
                set(instr.output, .jsAnything)
            }

        case .beginPlainFunction(let op as BeginAnyFunction),
             .beginArrowFunction(let op as BeginAnyFunction),
             .beginGeneratorFunction(let op as BeginAnyFunction),
             .beginAsyncFunction(let op as BeginAnyFunction),
             .beginAsyncArrowFunction(let op as BeginAnyFunction),
             .beginAsyncGeneratorFunction(let op as BeginAnyFunction):
            processParameterDeclarations(instr.innerOutputs, parameters: inferSubroutineParameterList(of: op, at: instr.index))

        case .beginConstructor(let op):
            // The first inner output is the explicit |this| parameter for the constructor
            set(instr.innerOutput(0), .object())
            processParameterDeclarations(instr.innerOutputs(1...), parameters: inferSubroutineParameterList(of: op, at: instr.index))

        case .callSuperMethod(let op):
            let sig = chooseUniform(from: inferMethodSignatures(of: op.methodName, on: currentSuperType()))
            set(instr.output, sig.outputType)

        case .getPrivateProperty:
            // We currently don't track the types of private properties
            set(instr.output, .jsAnything)

        case .callPrivateMethod:
            // We currently don't track the signatures of private methods
            set(instr.output, .jsAnything)

        case .getSuperProperty(let op):
            set(instr.output, inferPropertyType(of: op.propertyName, on: currentSuperType()))

            // TODO: support superclass property assignment

        case .beginForLoopCondition:
            // For now, we use only the initial type of the loop variables (at the point of the for-loop's initializer block)
            // without tracking any type changes in the other parts of the for loop.
            let inputTypes = instr.inputs.map({ state.type(of: $0) })
            activeForLoopVariableTypes.push(inputTypes)
            assert(inputTypes.count == instr.numInnerOutputs)
            zip(instr.innerOutputs, inputTypes).forEach({ set($0, $1) })

        case .beginForLoopAfterthought:
            let inputTypes = activeForLoopVariableTypes.top
            assert(inputTypes.count == instr.numInnerOutputs)
            zip(instr.innerOutputs, inputTypes).forEach({ set($0, $1) })

        case .beginForLoopBody:
            let inputTypes = activeForLoopVariableTypes.pop()
            assert(inputTypes.count == instr.numInnerOutputs)
            zip(instr.innerOutputs, inputTypes).forEach({ set($0, $1) })

        case .beginForInLoop:
            set(instr.innerOutput, .string)

        case .beginForOfLoop:
            set(instr.innerOutput, .jsAnything)

        case .beginForOfLoopWithDestruct:
            for v in instr.innerOutputs {
                set(v, .jsAnything)
            }

        case .beginRepeatLoop(let op):
            if op.exposesLoopCounter {
                set(instr.innerOutput, .integer)
            }

        case .beginCatch:
            set(instr.innerOutput, .jsAnything)

        // TODO: also add other macro instructions here.
        case .createWasmGlobal(let op):
            set(instr.output, .object(ofGroup: "WasmGlobal", withProperties: ["value"], withMethods: ["valueOf"], withWasmType: WasmGlobalType(valueType: op.value.toType(), isMutable: op.isMutable)))

        case .createWasmMemory(let op):
            set(instr.output, .wasmMemory(limits: op.memType.limits, isShared: op.memType.isShared, isMemory64: op.memType.isMemory64))

        case .createWasmTable(let op):
            set(instr.output, .wasmTable(wasmTableType: WasmTableType(elementType: op.tableType.elementType, limits: op.tableType.limits, isTable64: op.tableType.isTable64, knownEntries: [])))

        case .createWasmJSTag(_):
            set(instr.output, .object(ofGroup: "WasmTag", withWasmType: WasmTagType([.wasmExternRef], isJSTag: true)))

        case .createWasmTag(let op):
            set(instr.output, .object(ofGroup: "WasmTag", withWasmType: WasmTagType(op.parameterTypes)))

        case .wrapSuspending(_):
            // This operation takes a function but produces an object that can be called from WebAssembly.
            // TODO: right now this "loses" the signature of the JS function, this is unfortunate but won't break fuzzing, in the template we can just store the signature.
            // The WasmJsCall generator just won't work as it requires a callable.
            // In the future we should also attach a WasmTypeExtension to this object that stores the signature of input(0) here.
            set(instr.output, .object(ofGroup:"WasmSuspendingObject"))

        case .wrapPromising(_):
            // Here we basically pass through the type transparently as we just annotate this exported function as "promising"
            // It is still possible to call this function just like any other regular function and the Signature is also the same.
            set(instr.output, type(ofInput: 0))

        case .bindMethod(let op):
            let signature = chooseUniform(from: inferMethodSignatures(of: op.methodName, on: instr.input(0)))
            // We need to prepend the this argument now. We pick .object() here as the widest type because of the following:
            // - a lot of builtin methods (such as the ones on `Array.prototype`) work on any JavaScript object
            // - [$constructor.prototype.foo.bind] is a common pattern and the `this` would be set to the type of constructor.prototype instead of the constructor's instance type.
            let newParameters = [Parameter.plain(.object())] + signature.parameters
            set(instr.output, .function(newParameters => signature.outputType))

        case .bindFunction(_):
            let inputType = type(ofInput: 0)
            if let signature = inputType.signature {
                if instr.inputs.count == 1 {
                    set(instr.output, inputType)
                } else {
                    // We only bind any actual parameters if the BindFunction operation has more
                    // than 2 inputs(instr.inputs.count - 2) as the first input is the function
                    // on which we call .bind() and the second input is the receiver, so the bind
                    // only replaces the existing receiver.
                    let start = min(instr.inputs.count - 2, signature.parameters.count)
                    let params = Array(signature.parameters[start..<signature.parameters.count])
                    set(instr.output, .function(params => signature.outputType))
                }
            } else {
                set(instr.output, .jsAnything)
            }

        case .wasmBeginTypeGroup(_):
            startTypeGroup()

        case .wasmEndTypeGroup(_):
            // For now just forward the type information based on the inputs.
            zip(instr.inputs, instr.outputs).forEach {input, output in
                set(output, state.type(of: input))
            }
            finishTypeGroup()

        case .wasmDefineSignatureType(let op):
            addSignatureType(def: instr.output, signature: op.signature, inputs: instr.inputs)

        case .wasmDefineArrayType(let op):
            let elementRef = op.elementType.requiredInputCount() == 1 ? instr.input(0) : nil
            addArrayType(def: instr.output, elementType: op.elementType, mutability: op.mutability, elementRef: elementRef)

        case .wasmDefineStructType(let op):
            var inputIndex = 0
            let fieldsWithRefs: [(WasmStructTypeDescription.Field, Variable?)] = op.fields.map { field in
                if field.type.requiredInputCount() == 0 {
                    return (field, nil)
                } else {
                    let ret = (field, instr.input(inputIndex))
                    inputIndex += 1
                    return ret
                }
            }
            assert(inputIndex == instr.inputs.count)
            addStructType(def: instr.output, fieldsWithRefs: fieldsWithRefs)

        case .wasmDefineForwardOrSelfReference(_):
            set(instr.output, .wasmSelfReference())

        case .wasmResolveForwardReference(_):
            // Resolve all usages of the forward reference (if any).
            if let resolvers = selfReferences[instr.input(0)] {
                for resolve in resolvers {
                    resolve(&self, instr.input(1))
                }
                // Reset the resolvers as the usages have been updated. The self reference can now
                // be used as a self reference again or resolved to a forward reference at a later
                // point in time again.
                selfReferences[instr.input(0)] = []
            }

        default:
            // Only simple instructions and block instruction with inner outputs are handled here
            assert(instr.isNop || (instr.numOutputs == 0 || (instr.isBlock && instr.numInnerOutputs == 0)))
        }

        // We explicitly type the outputs of guarded operations as .jsAnything for two reasons:
        // (1) if the operation raises an exception, then the output will probably be `undefined`
        //     but that's not clearly specified
        // (2) typing to .jsAnything allows us try and fix the operation at runtime (e.g. by looking
        //     at the existing methods for a method call or by selecting different inputs), in
        //     which case the return value may change. See FixupMutator.swift for more details.
        if instr.hasOutputs && instr.isGuarded {
            assert(instr.numInnerOutputs == 0)
            instr.allOutputs.forEach({ set($0, .jsAnything) })
        }

        // We should only have parameter types for operations that start a subroutine, otherwise, something is inconsistent.
        // We could put this assert elsewhere as well, but here seems fine.
        assert(instr.op is BeginAnySubroutine || signatures[instr.index] == nil)
    }

    private func computeParameterTypes(from parameters: ParameterList) -> [ILType] {
        var types: [ILType] = []
        parameters.forEach { param in
            switch param {
            case .plain(let t):
                types.append(t)
            case .opt(let t):
                types.append(t | .undefined)
            case .rest:
                // A rest parameter will just be an array. Currently, we don't support nested array types (i.e. .iterable(of: .integer)) or so, but once we do, we'd need to update this logic.
                types.append(.jsArray)
            }
        }
        return types
    }

    private struct AnalyzerState {
        // Represents the execution state at one point in a CFG.
        //
        // This must be a reference type as it is referred to from
        // member variables as well as being part of the state stack.
        private class State {
            var types = VariableMap<ILType>()

            // Whether this state represents a subroutine, in which case it also
            // tracks its return value type.
            let isSubroutineState: Bool
            // Holds the current type of the return value. This is also tracked in
            // states that are not subroutines, as one of their parent states may
            // be a subroutine.
            var returnValueType = ILType.nothing
            // Whether all execution paths leading to this state have already returned,
            // in which case the return value type will not be updated again.
            var hasReturned = false

            // Whether this state represents a switch default case, which requires
            // special handling: if there is a default case in a switch, then one
            // of the cases is guaranteed to execute, otherwise not.
            let isDefaultSwitchCaseState: Bool

            init(isSubroutineState: Bool = false, isDefaultSwitchCaseState: Bool = false) {
                assert(!isSubroutineState || !isDefaultSwitchCaseState)
                self.isSubroutineState = isSubroutineState
                self.isDefaultSwitchCaseState = isDefaultSwitchCaseState
            }
        }

        // The current execution state. There is a new level (= array of states)
        // pushed onto this stack for every CFG structure with conditional execution
        // (if-else, loops, ...). Each level then has as many states as there are
        // conditional branches, e.g. if-else has two states, if-elseif-elseif-else
        // would have four and so on.
        //
        // Each state in the stack only stores information that was updated in the
        // corresponding block. As such, there may be a type for a variable in a
        // parent state but not a child state (if the variable's type doesn't change
        // inside the child block). However, there's an invariant that if the active
        // state contains a type (that's not .nothing, see below) for V, then its
        // parent state must also contain a type for V: if the variable is only defined
        // in the child state, it's type in the parent state will be set to .nothing.
        // If the variable is changed in a child state but not its parent state, then
        // the type in the parent state will be the most recent type for V in its parent
        // states. This invariant is necessary to be able to correctly update types when
        // leaving scopes as that requires knowing the type in the surrounding scope.
        //
        // It would be simpler to have the types of all visible variables in all active
        // states, but this way of implementing state tracking is significantly faster.
        private var states: Stack<[State]>

        // Always points to the active state: the newest state in the top most level of the stack
        private var activeState: State
        // Always points to the parent state: the newest state in the second-to-top level of the stack
        private var parentState: State

        // The full state at the current position. In essence, this is just a cache.
        // The same information could be retrieved by walking the state stack starting
        // from the activeState until there is a value for the queried variable.
        private var overallState: State

        init() {
            activeState = State()
            parentState = State()
            states = Stack([[parentState], [activeState]])
            overallState = State()
        }

        mutating func reset() {
            self = AnalyzerState()
        }

        /// Return the current type of the given variable.
        /// Return .jsAnything for variables not available in this state.
        func type(of variable: Variable) -> ILType {
            return overallState.types[variable] ?? .jsAnything
        }

        func hasType(for v: Variable) -> Bool {
            return overallState.types[v] != nil
        }

        /// Set the type of the given variable in the current state.
        mutating func updateType(of v: Variable, to newType: ILType, from oldType: ILType? = nil) {
            // Basic consistency checking. This seems like a decent
            // place to do this since it executes frequently.
            assert(activeState === states.top.last!)
            assert(parentState === states.secondToTop.last!)
            // If an oldType is specified, it must match the type in the next most recent state
            // (but here we just check that one of the parent states contains it).
            assert(oldType == nil || states.elementsStartingAtTop().contains(where: { $0.last!.types[v] == oldType! }))

            // Set the old type in the parent state if it doesn't yet exist to satisfy "activeState[v] != nil => parentState[v] != nil".
            // Use .nothing to express that the variable is only defined in the child state.
            let oldType = oldType ?? overallState.types[v] ?? .nothing
            if parentState.types[v] == nil {
                parentState.types[v] = oldType
            }

            // Integrity checking: if the type of v hasn't previously been updated in the active
            // state, then the old type must be equal to the type in the parent state.
            assert(activeState.types[v] != nil || parentState.types[v] == oldType)

            activeState.types[v] = newType
            overallState.types[v] = newType
        }

        mutating func updateReturnValueType(to t: ILType) {
            assert(states.elementsStartingAtTop().contains(where: { $0.last!.isSubroutineState }), "Handling a `return` but neither the active state nor any of its parent states represents a subroutine")
            guard !activeState.hasReturned else {
                // In this case, we have already set the return value in this branch of (conditional)
                // execution and so are executing inside dead code, so don't update the return value.
                return
            }
            activeState.returnValueType |= t
            activeState.hasReturned = true
        }

        /// Start a new group of conditionally executing blocks.
        ///
        /// At runtime, exactly one of the blocks in this group (added via `enterConditionallyExecutingBlock`) will be
        /// executed. A group of conditionally executing blocks should consist of at least two blocks, otherwise
        /// the single block will be treated as executing unconditionally.
        /// For example, an if-else would be represented by a group of two blocks, while a group representing
        /// a switch-case may contain many blocks. However, a switch-case consisting only of a default case is a
        /// a legitimate example of a group of blocks consisting of a single block (which then executes unconditionally).
        mutating func startGroupOfConditionallyExecutingBlocks() {
            parentState = activeState
            states.push([])
        }

        /// Enter a new conditionally executing block and append it to the currently active group of such blocks.
        /// As such, either this block or one of its "sibling" blocks in the current group may execute at runtime.
        mutating func enterConditionallyExecutingBlock(typeChanges: inout [(Variable, ILType)], isDefaultSwitchCaseState: Bool = false) {
            assert(states.top.isEmpty || !states.top.last!.isSubroutineState)

            // Reset current state to parent state
            for (v, t) in activeState.types {
                // Do not save type change if
                // 1. Variable does not exist in sibling scope (t == .nothing)
                // 2. Variable is only local in sibling state (parent == .nothing)
                // 3. No type change happened
                if t != .nothing && parentState.types[v] != .nothing && parentState.types[v] != overallState.types[v] {
                    typeChanges.append((v, parentState.types[v]!))
                    overallState.types[v] = parentState.types[v]!
                }
            }

            activeState = State(isDefaultSwitchCaseState: isDefaultSwitchCaseState)
            states.top.append(activeState)
        }

        /// Finalize the current group of conditionally executing blocks.
        ///
        /// This will compute the new variable types assuming that exactly one of the blocks in the group will be executed
        /// at runtime and will then return to the previously active state.
        mutating func endGroupOfConditionallyExecutingBlocks(typeChanges: inout [(Variable, ILType)]) {
            let returnValueType = mergeNewestConditionalBlocks(typeChanges: &typeChanges, defaultReturnValueType: .nothing)
            assert(returnValueType == nil)
        }

        /// Start a new group of conditionally executing blocks representing a switch construct.
        ///
        /// We have special handling for switch blocks since they are a bit special: if there is a default
        /// case in a switch, then it's guaranteed that exactly one of the cases will execute at runtime.
        /// Otherwise, this is not guaranteed.
        mutating func startSwitch() {
            startGroupOfConditionallyExecutingBlocks()
        }

        /// Enter a new conditionally executing block representing a (regular) switch case.
        mutating func enterSwitchCase(typeChanges: inout [(Variable, ILType)]) {
            enterConditionallyExecutingBlock(typeChanges: &typeChanges)
        }

        /// Enter a new conditionally executing block representing a default switch case.
        mutating func enterSwitchDefaultCase(typeChanges: inout [(Variable, ILType)]) {
            enterConditionallyExecutingBlock(typeChanges: &typeChanges, isDefaultSwitchCaseState: true)
        }

        /// Finalizes the current group of conditionally executing blocks representing a switch construct.
        mutating func endSwitch(typeChanges: inout [(Variable, ILType)]) {
            // First check if we have a default case. If not, we need to add an empty state
            // that represents the scenario in which none of the cases is executed.
            // TODO: in case of multiple switch default cases, we should ignore all but the first one.
            let hasDefaultCase = states.top.contains(where: { $0.isDefaultSwitchCaseState })
            if !hasDefaultCase {
                // No default case, so add an empty state for the case that no case block is executed.
                enterConditionallyExecutingBlock(typeChanges: &typeChanges)
            }
            endGroupOfConditionallyExecutingBlocks(typeChanges: &typeChanges)
        }

        /// Whether the currently active block has at least one alternative block.
        var currentBlockHasAlternativeBlock: Bool {
            return states.top.count > 1
        }

        /// Start a new subroutine.
        ///
        /// Subroutines are treated as conditionally executing code, in essence similar to
        ///
        ///     if (functionIsCalled) {
        ///         function_body();
        ///     }
        ///
        /// In addition to updating variable types, subroutines also track their return value
        /// type which is returned by `leaveSubroutine()`.
        mutating func startSubroutine() {
            parentState = activeState
            // The empty state represents the execution path where the function is not executed.
            let emptyState = State()
            activeState = State(isSubroutineState: true)
            states.push([emptyState, activeState])
        }

        /// End the current subroutine.
        ///
        /// This behaves similar to `endGroupOfConditionallyExecutingBlocks()` and computes variable type changes assuming that the\
        /// function body may or may not have been executed, but it additionally computes and returns the inferred type for the subroutine's return value.
        mutating func endSubroutine(typeChanges: inout [(Variable, ILType)], defaultReturnValueType: ILType) -> ILType {
            guard let returnValueType = mergeNewestConditionalBlocks(typeChanges: &typeChanges, defaultReturnValueType: defaultReturnValueType) else {
                fatalError("Leaving a subroutine that was never entered")
            }
            return returnValueType
        }

        /// Merge the current conditional block and all its alternative blocks and compute both variable- and return value type changes.
        ///
        /// This computes the new types assuming that exactly one of the conditional blocks will execute at runtime. If the currently
        /// active state is a subroutine state, this will return the final return value type, otherwise it will return nil.
        private mutating func mergeNewestConditionalBlocks(typeChanges: inout [(Variable, ILType)], defaultReturnValueType: ILType) -> ILType? {
            let statesToMerge = states.pop()

            let maybeReturnValueType = computeReturnValueType(whenMerging: statesToMerge, defaultReturnValueType: defaultReturnValueType)
            let newTypes = computeVariableTypes(whenMerging: statesToMerge)
            makeParentStateTheActiveStateAndUpdateVariableTypes(to: newTypes, &typeChanges)

            return maybeReturnValueType
        }

        private func computeReturnValueType(whenMerging states: [State], defaultReturnValueType: ILType) -> ILType? {
            assert(states.last === activeState)

            // Need to compute how many sibling states have returned and what their overall return value type is.
            var returnedStates = 0
            var returnValueType = ILType.nothing

            for state in states {
                returnValueType |= state.returnValueType
                if state.hasReturned {
                    assert(state.returnValueType != .nothing)
                    returnedStates += 1
                }
            }

            // If the active state represents a subroutine, then we can now compute
            // the final return value type.
            // Otherwise, we may need to merge our return value type with that
            // of our parent state.
            var maybeReturnValue: ILType? = nil
            if activeState.isSubroutineState {
                assert(returnValueType == activeState.returnValueType)
                if !activeState.hasReturned {
                    returnValueType |= defaultReturnValueType
                }
                maybeReturnValue = returnValueType
            } else if !parentState.hasReturned {
                parentState.returnValueType |= returnValueType
                if returnedStates == states.count {
                    // All conditional branches have returned, so the parent state
                    // must also have returned now.
                    parentState.hasReturned = true
                }
            }
            // None of our sibling states can be a subroutine state as that wouldn't make sense semantically.
            assert(states.dropLast().allSatisfy({ !$0.isSubroutineState }))

            return maybeReturnValue
        }

        private func computeVariableTypes(whenMerging states: [State]) -> VariableMap<ILType> {
            var numUpdatesPerVariable = VariableMap<Int>()
            var newTypes = VariableMap<ILType>()

            for state in states {
                for (v, t) in state.types {
                    // Skip variable types that are already out of scope (local to a child of the child state)
                    guard t != .nothing else { continue }

                    // Invariant checking: activeState[v] != nil => parentState[v] != nil
                    assert(parentState.types[v] != nil)

                    // Skip variables that are local to the child state
                    guard parentState.types[v] != .nothing else { continue }

                    if newTypes[v] == nil {
                        newTypes[v] = t
                        numUpdatesPerVariable[v] = 1
                    } else {
                        newTypes[v]! |= t
                        numUpdatesPerVariable[v]! += 1
                    }
                }
            }

            for (v, c) in numUpdatesPerVariable {
                assert(parentState.types[v] != .nothing)

                // Not all paths updates this variable, so it must be unioned with the type in the parent state.
                // The parent state will always have an entry for v due to the invariant "activeState[v] != nil => parentState[v] != nil".
                if c != states.count {
                    newTypes[v]! |= parentState.types[v]!
                }
            }

            return newTypes
        }

        private mutating func makeParentStateTheActiveStateAndUpdateVariableTypes(to newTypes: VariableMap<ILType>, _ typeChanges: inout [(Variable, ILType)]) {
            // The previous parent state is now the active state
            let oldParentState = parentState
            activeState = parentState
            parentState = states.secondToTop.last!
            assert(activeState === states.top.last)

            // Update the overallState and compute typeChanges
            for (v, newType) in newTypes {
                if overallState.types[v] != newType {
                    typeChanges.append((v, newType))
                }

                // overallState now doesn't contain the older type but actually a newer type,
                // therefore we have to manually specify the old type here.
                updateType(of: v, to: newType, from: oldParentState.types[v])
            }
        }
    }
}
