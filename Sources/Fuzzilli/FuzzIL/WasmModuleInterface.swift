// Copyright 2026 Google LLC
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

import OrderedCollections

/// The interface of a Wasm module towards JavaScript: the objects that the module imports and the
/// names under which the lifted module exports its imports and definitions.
///
/// The JSTyper records the interface while it analyzes a Wasm module and derives the type of the
/// `exports` object of the module's instance from it. The WasmLifter builds the import and export
/// sections of the module from the typer's interface, so the typer's view of the exports can't get
/// out of sync with the actual exports of the lifted module.
public struct WasmModuleInterface {
    /// The kinds of objects that a Wasm module imports, defines and exports.
    public enum Kind: CaseIterable {
        // The order of the cases is the order of the exports in the export section.
        case function
        case global
        case table
        case memory
        case tag

        fileprivate var exportNamePrefix: String {
            switch self {
            case .function: return "w"
            case .global: return "wg"
            case .table: return "wt"
            case .memory: return "wm"
            case .tag: return "wex"
            }
        }
    }

    /// A module can import the same JavaScript function multiple times with different signatures,
    /// so function imports are identified by their variable and this signature.
    public enum FunctionSignature: Hashable {
        /// The signature of a WasmJsCall that calls the function.
        case wasmSignature(WasmSignature)
        /// The signature type definition of a WasmDefineTable entry that holds the function.
        case signatureDef(Variable)
    }

    public struct Import: Hashable {
        public let kind: Kind
        public let variable: Variable
        /// The signature of a function import, nil for all other kinds.
        public let functionSignature: FunctionSignature?
    }

    public struct Definition {
        public let kind: Kind
        public let variable: Variable
    }

    public struct Export {
        /// The name under which the lifted module exports the object, e.g. "w0" or "iwt1".
        public let name: String
        public let kind: Kind
        /// The exported variable, which is either imported or the output of a definition.
        public let variable: Variable
        /// The import if the module re-exports one of its imports, nil if it exports a definition.
        public let reexportedImport: Import?
    }

    /// The imports in the order in which the module first uses them.
    public private(set) var imports = OrderedSet<Import>()
    /// The definitions in the order in which the module defines them.
    public private(set) var definitions: [Definition] = []

    private var definedVariables = Set<Variable>()

    /// Records the imports and definitions of the given instruction, which has to be the next
    /// instruction of the module. `typeOf` has to return the current type of a variable.
    ///
    /// An instruction imports the tables, memories, globals and tags that it takes as inputs, unless
    /// they are defined in this module. Objects defined in an earlier module are imported, too, as
    /// they are only accessible through the `exports` object of that module's instance. Functions
    /// and suspending objects are only imported by WasmJsCall and WasmDefineTable. (The WasmLifter
    /// fails for other operations with such inputs.) Each object is imported once, except for
    /// functions, which are imported once per signature.
    public mutating func record(_ instr: Instruction, typeOf: (Variable) -> ILType) {
        for (idx, input) in instr.inputs.enumerated() where !definedVariables.contains(input) {
            let type = typeOf(input)
            if type.Is(.object(ofGroup: "WasmTable")) {
                addImport(.table, input)
            } else if type.Is(.object(ofGroup: "WasmMemory")) {
                addImport(.memory, input)
            } else if type.Is(.object(ofGroup: "WasmGlobal")) {
                addImport(.global, input)
            } else if type.Is(.object(ofGroup: "WasmTag")) {
                // The WasmLifter can't import a tag without knowing its type and fails instead.
                if type.isWasmTagType {
                    addImport(.tag, input)
                }
            } else if type.Is(.function()) || type.Is(.object(ofGroup: "WasmSuspendingObject")) {
                switch instr.op.opcode {
                case .wasmJsCall(_):
                    let signatureType = typeOf(instr.input(0))
                    if signatureType.isWasmSignatureTypeDef {
                        addImport(
                            .function, input,
                            .wasmSignature(signatureType.wasmFunctionSignatureDefSignature))
                    }
                case .wasmDefineTable(_):
                    // The inputs are pairs of a function and its signature type definition.
                    if idx % 2 == 0 {
                        addImport(.function, input, .signatureDef(instr.input(idx + 1)))
                    }
                default:
                    break
                }
            } else {
                // Other inputs, e.g. Wasm values, labels and type definitions, aren't imported.
            }
        }

        let definedKind: Kind? =
            switch instr.op.opcode {
            case .endWasmFunction(_): .function
            case .wasmDefineGlobal(_): .global
            case .wasmDefineTable(_): .table
            case .wasmDefineMemory(_): .memory
            case .wasmDefineTag(_): .tag
            default: nil
            }
        if let definedKind {
            definitions.append(Definition(kind: definedKind, variable: instr.output))
            definedVariables.insert(instr.output)
        }
    }

    private mutating func addImport(
        _ kind: Kind, _ variable: Variable, _ functionSignature: FunctionSignature? = nil
    ) {
        // Only adds the import if the module doesn't import it already.
        imports.append(Import(kind: kind, variable: variable, functionSignature: functionSignature))
    }

    /// The module exports all of its imports and definitions. The exports are ordered like in the
    /// export section: grouped by kind, with the re-exported imports of a kind before its
    /// definitions.
    public var exports: [Export] {
        var exports = [Export]()
        for kind in Kind.allCases {
            for (index, imp) in imports.filter({ $0.kind == kind }).enumerated() {
                exports.append(
                    Export(
                        name: Self.exportName(of: kind, index: index, isImport: true), kind: kind,
                        variable: imp.variable, reexportedImport: imp))
            }
            for (index, definition) in definitions.filter({ $0.kind == kind }).enumerated() {
                exports.append(
                    Export(
                        name: Self.exportName(of: kind, index: index, isImport: false), kind: kind,
                        variable: definition.variable, reexportedImport: nil))
            }
        }
        return exports
    }

    /// The name under which the lifted module exports its `index`-th import or definition of the
    /// given kind, e.g. "w0" for the first defined function or "iwt1" for the second imported table.
    public static func exportName(of kind: Kind, index: Int, isImport: Bool) -> String {
        return (isImport ? "i" : "") + kind.exportNamePrefix + String(index)
    }
}
