// Copyright 2022 Google LLC
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

/// This mutator inserts probes into a program to determine how existing variables are used.
///
/// Its main purpose is to determine which (non-existent) properties are accessed on existing objects and to then add these properties (or install accessors for them).
///
/// This mutator achieves this by doing the following:
/// 1. It instruments the given program by inserting special Probe operations which turn an existing variable into a "probe"
///   that records accesses to non-existent properties on the original value. In JavaScript, probing is implemented by
///   replacing an object's prototype with a Proxy around the original prototype. This Proxy will then see all accesses to
///   non-existent properties. Alternatively, the probed object itself could be replaced with a Proxy, however that will
///   cause various builtin methods to fail because they for example expect |this| to have a specific type.
/// 2. It executes the instrumented program. The program collects the property names of non-existent properties that were accessed
///   on a probe and reports this information to Fuzzilli through the FUZZOUT channel at the end of the program's execution.
/// 3. The mutator processes the output of step 2 and randomly selects properties to install (either as plain value or
///   accessor). It then converts the Probe operations to an appropriate FuzzIL operation (e.g. SetProperty).
///
/// A large bit of the logic of this mutator is located in the lifter code that implements Probe operations
/// in the target language. For JavaScript, that logic can be found in JavaScriptProbeLifting.swift.
public class ProbingMutator: RuntimeAssistedMutator {
    // If true, this mutator will log detailed statistics like how often each type of operation was performend.
    private static let verbose = true

    // Statistics about how often we've installed a particular property. Printed in regular intervals if verbose mode is active, then reset.
    private var installedPropertiesForGetAccess = [Property: Int]()
    private var installedPropertiesForSetAccess = [Property: Int]()
    // Counts the total number of installed properties installed. Printed in regular intervals if verbose mode is active, then reset.
    private var installedPropertyCounter = 0

    // Track the average number of inserted probes, for statistical purposes.
    private var averageNumberOfInsertedProbes = MovingAverage(n: 1000)

    // Normally, we will not overwrite properties that already exist on the prototype (e.g. Array.prototype.slice). This list contains the exceptions to this rule.
    private let propertiesOnPrototypeToOverwrite = ["valueOf", "toString", "constructor"]

    public init() {
        super.init("ProbingMutator", verbose: ProbingMutator.verbose)
    }

    override func instrument(_ program: Program, for fuzzer: Fuzzer) -> Program? {
        // Determine candidates for probing: every variable that is used at least once as an input is a candidate.
        var usedVariables = VariableSet()
        for instr in program.code {
            // TODO: we currently don't want to explore anything in the wasm world.
            // We might want to change this to explore the functions that the Wasm module emits.
            guard !(instr.op is WasmOperation) else { continue }

            usedVariables.formUnion(instr.inputs)
        }
        let candidates = Array(usedVariables)
        guard !candidates.isEmpty else { return nil }

        // Select variables to instrument from the candidates.
        let numVariablesToProbe = Int((Double(candidates.count) * 0.50).rounded(.up))
        let variablesToProbe = VariableSet(candidates.shuffled().prefix(numVariablesToProbe))

        // We only want to instrument outer outputs of block heads after the end of that block.
        // For example, a function definition should be turned into a probe not inside its body
        // but right after the function definition ends in the surrounding block.
        // For that reason, we keep a stack of pending variables that need to be probed once
        // the block that they are the output of is closed.
        var pendingProbesStack = Stack<Variable?>()
        let b = fuzzer.makeBuilder()
        b.adopting(from: program) {
            for instr in program.code {
                b.adopt(instr)

                if instr.isBlockGroupStart {
                    pendingProbesStack.push(nil)
                } else if instr.isBlockGroupEnd {
                    if let v = pendingProbesStack.pop() {
                        b.probe(v, id: v.identifier)
                    }
                }

                for v in instr.innerOutputs where variablesToProbe.contains(v) {
                    b.probe(v, id: v.identifier)
                }
                for v in instr.outputs where variablesToProbe.contains(v) {
                    if instr.isBlockGroupStart {
                        pendingProbesStack.top = v
                    } else {
                        b.probe(v, id: v.identifier)
                    }
                }
            }
        }

        let instrumentedProgram = b.finalize()
        let numberOfInsertedProbes = instrumentedProgram.code.filter({ $0.op is Probe }).count
        averageNumberOfInsertedProbes.add(Double(numberOfInsertedProbes))
        return instrumentedProgram
    }

    override func process(_ output: String, ofInstrumentedProgram instrumentedProgram: Program, using b: ProgramBuilder) -> (Program?, RuntimeAssistedMutator.Outcome) {
        assert(instrumentedProgram.code.contains(where: { $0.op is Probe }))

        // Parse the output: look for either "PROBING_ERROR" or "PROBING_RESULTS" and process the content.
        var results = [String: Result]()
        for line in output.split(whereSeparator: \.isNewline) where line.starts(with: "PROBING") {
            let errorMarker = "PROBING_ERROR: "
            let resultsMarker = "PROBING_RESULTS: "

            if line.hasPrefix(errorMarker) {
                if isKnownRuntimeError(line) { return (nil, .instrumentedProgramFailed) }
                // Everything else is unexpected and probably means that there's a bug in the JavaScript implementation, so treat that as an error.
                logger.error("\nProbing failed: \(line.dropFirst(errorMarker.count))\n")
                // We could probably still continue in these cases, but since this is unexpected, it's probably better to stop here and treat this as an unexpected failure.
                return (nil, .unexpectedError)
            }

            guard line.hasPrefix(resultsMarker) else {
                logger.error("Invalid probing result: \(line)")
                return (nil, .unexpectedError)
            }

            let decoder = JSONDecoder()
            let payload = Data(line.dropFirst(resultsMarker.count).utf8)
            guard let decodedResults = try? decoder.decode([String: Result].self, from: payload) else {
                logger.error("Failed to decode JSON payload in \"\(line)\"")
                return (nil, .unexpectedError)
            }
            results = decodedResults
        }

        guard !results.isEmpty else {
            return (nil, .noResults)
        }

        // Now build the final program by parsing the results and replacing the Probe operations
        // with FuzzIL operations that install one of the non-existent properties (if any).
        b.adopting(from: instrumentedProgram) {
            for instr in instrumentedProgram.code {
                if let op = instr.op as? Probe {
                    if let results = results[op.id] {
                        let probedValue = b.adopt(instr.input(0))
                        b.trace("Probing value \(probedValue)")
                        processProbeResults(results, on: probedValue, using: b)
                        b.trace("Probing finished")
                    }
                } else {
                    b.adopt(instr)
                }
            }
        }

        return (b.finalize(), .success)
    }

    override func logAdditionalStatistics() {
        logger.verbose("Average number of inserted probes: \(String(format: "%.2f", averageNumberOfInsertedProbes.currentValue))")
        logger.verbose("Properties installed during recent mutations (in total: \(installedPropertyCounter)):")
        var statsAsList = installedPropertiesForGetAccess.map({ (key: $0, count: $1, op: "get") })
        statsAsList +=   installedPropertiesForSetAccess.map({ (key: $0, count: $1, op: "set") })
        for (key, count, op) in statsAsList.sorted(by: { $0.count > $1.count }) {
            let type = isCallableProperty(key) ? "function" : "anything"
            logger.verbose("    \(count)x \(key.description) (access: \(op), type: \(type))")
        }

        installedPropertiesForGetAccess.removeAll()
        installedPropertiesForSetAccess.removeAll()
        installedPropertyCounter = 0
    }

    private func processProbeResults(_ result: Result, on obj: Variable, using b: ProgramBuilder) {
        // Extract all candidates: properties that are accessed but not present (or explicitly marked as overwritable).
        let loadCandidates = result.loads.filter({ $0.value == .notFound || ($0.value == .found && propertiesOnPrototypeToOverwrite.contains($0.key)) }).map({ $0.key })
        // For stores we only care about properties that don't exist anywhere on the prototype chain.
        let storeCandidates = result.stores.filter({ $0.value == .notFound }).map({ $0.key })
        let candidates = Set(loadCandidates).union(storeCandidates)
        guard !candidates.isEmpty else { return }

        // Pick a random property from the candidates.
        let propertyName = chooseUniform(from: candidates)
        let propertyIsLoaded = result.loads.keys.contains(propertyName)
        let propertyIsStored = result.stores.keys.contains(propertyName)

        // Install the property, either as regular property or as a property accessor.
        guard let property = parsePropertyName(propertyName) else { return }
        if probability(0.8) {
            installRegularProperty(property, on: obj, using: b)
        } else {
            installPropertyAccessor(for: property, on: obj, using: b, shouldHaveGetter: propertyIsLoaded, shouldHaveSetter: propertyIsStored)
        }

        // Update our statistics.
        if verbose && propertyIsLoaded {
            installedPropertiesForGetAccess[property] = (installedPropertiesForGetAccess[property] ?? 0) + 1
        }
        if verbose && propertyIsStored {
            installedPropertiesForSetAccess[property] = (installedPropertiesForSetAccess[property] ?? 0) + 1
        }
        installedPropertyCounter += 1
    }

    private func installRegularProperty(_ property: Property, on obj: Variable, using b: ProgramBuilder) {
        let value = selectValue(for: property, using: b)

        switch property {
        case .regular(let name):
            assert(isValidPropertyName(name))
            b.setProperty(name, of: obj, to: value)
        case .element(let index):
            b.setElement(index, of: obj, to: value)
        case .symbol(let desc):
            let Symbol = b.createNamedVariable(forBuiltin: "Symbol")
            let symbol = b.getProperty(extractSymbolNameFromDescription(desc), of: Symbol)
            b.setComputedProperty(symbol, of: obj, to: value)
        }
    }

    private func installPropertyAccessor(for property: Property, on obj: Variable, using b: ProgramBuilder, shouldHaveGetter: Bool, shouldHaveSetter: Bool) {
        assert(shouldHaveGetter || shouldHaveSetter)
        let installAsValue = probability(0.5)
        let installGetter = !installAsValue && (shouldHaveGetter || probability(0.5))
        let installSetter = !installAsValue && (shouldHaveSetter || probability(0.5))

        let config: ProgramBuilder.PropertyConfiguration
        if installAsValue {
            config = .value(selectValue(for: property, using: b))
        } else if installGetter && installSetter {
            let getter = b.buildPlainFunction(with: .parameters(n: 0)) { _ in
                let value = selectValue(for: property, using: b)
                b.doReturn(value)
            }
            let setter = b.buildPlainFunction(with: .parameters(n: 1)) { _ in
                b.build(n: 1)
            }
            config = .getterSetter(getter, setter)
        } else if installGetter {
            let getter = b.buildPlainFunction(with: .parameters(n: 0)) { _ in
                let value = selectValue(for: property, using: b)
                b.doReturn(value)
            }
            config = .getter(getter)
        } else {
            assert(installSetter)
            let setter = b.buildPlainFunction(with: .parameters(n: 1)) { _ in
                b.build(n: 1)
            }
            config = .setter(setter)
        }

        switch property {
        case .regular(let name):
            assert(isValidPropertyName(name))
            b.configureProperty(name, of: obj, usingFlags: PropertyFlags.random(), as: config)
        case .element(let index):
            b.configureElement(index, of: obj, usingFlags: PropertyFlags.random(), as: config)
        case .symbol(let desc):
            let Symbol = b.createNamedVariable(forBuiltin: "Symbol")
            let symbol = b.getProperty(extractSymbolNameFromDescription(desc), of: Symbol)
            b.configureComputedProperty(symbol, of: obj, usingFlags: PropertyFlags.random(), as: config)
        }
    }

    private func extractSymbolNameFromDescription(_ desc: String) -> String {
        // Well-known symbols are of the form "Symbol.toPrimitive". All other symbols should've been filtered out by the instrumented code.
        let wellKnownSymbolPrefix = "Symbol."
        guard desc.hasPrefix(wellKnownSymbolPrefix) else {
            logger.error("Received invalid symbol property from instrumented code: \(desc)")
            return desc
        }
        return String(desc.dropFirst(wellKnownSymbolPrefix.count))
    }

    private func isCallableProperty(_ property: Property) -> Bool {
        let knownFunctionPropertyNames = ["valueOf", "toString", "constructor", "then", "next", "get", "set"]
        let knownNonFunctionSymbolNames = ["Symbol.isConcatSpreadable", "Symbol.unscopables", "Symbol.toStringTag"]

        // Check if the property should be a function.
        switch property {
        case .regular(let name):
            return knownFunctionPropertyNames.contains(name)
        case .symbol(let desc):
            return !knownNonFunctionSymbolNames.contains(desc)
        case .element(_):
            return false
        }
    }

    private func selectValue(for property: Property, using b: ProgramBuilder) -> Variable {
        if isCallableProperty(property) {
            // Either create a new function or reuse an existing one
            let probabilityOfReusingExistingFunction = 2.0 / 3.0
            if let f = b.randomVariable(ofType: .function()), probability(probabilityOfReusingExistingFunction) {
                return f
            } else {
                let f = b.buildPlainFunction(with: .parameters(n: Int.random(in: 0..<3))) { args in
                    b.build(n: 2)       // TODO maybe forbid generating any nested blocks here?
                    b.doReturn(b.randomVariable())
                }
                return f
            }
        } else {
            // Otherwise, just return a random variable.
            return b.randomVariable()
        }
    }

    private func isValidPropertyName(_ name: String) -> Bool {
        // Currently only property names containing whitespaces or newlines are invalid.
        return name.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
    }

    private func parsePropertyName(_ propertyName: String) -> Property? {
        // Anything that parses as an Int64 is an element index.
        if let index = Int64(propertyName) {
            return .element(index)
        }

        // Symbols will be encoded as "Symbol(symbolDescription)".
        let symbolPrefix = "Symbol("
        let symbolSuffix = ")"
        if propertyName.hasPrefix(symbolPrefix) && propertyName.hasSuffix(symbolSuffix) {
            let desc = propertyName.dropFirst(symbolPrefix.count).dropLast(symbolSuffix.count)
            return .symbol(String(desc))
        }

        // Everything else is a regular property name.
        guard isValidPropertyName(propertyName) else {
            // Invalid property names should have been filtered out on the JavaScript side, so receiving them here is an error.
            logger.error("Received invalid property name: \(propertyName)")
            return nil
        }
        return .regular(propertyName)
    }

    private enum Property: Hashable, CustomStringConvertible {
        case regular(String)
        case symbol(String)
        case element(Int64)

        var description: String {
            switch self {
            case .regular(let name):
                return name
            case .symbol(let desc):
                return desc
            case .element(let index):
                return String(index)
            }
        }
    }

    private struct Result: Decodable {
        enum outcome: Int, Decodable {
            case notFound = 0
            case found = 1
        }
        let loads: [String: outcome]
        let stores: [String: outcome]
    }
}
