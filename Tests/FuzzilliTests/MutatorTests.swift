// Copyright 2025 Google LLC
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

import Testing
import XCTest

@testable import Fuzzilli

class MutatorTests: XCTestCase {
    func testSpliceMutatorWasmTypeGroups() {
        let env = JavaScriptEnvironment()
        let config = Configuration(logLevel: .error)
        let fuzzer = makeMockFuzzer(config: config, environment: env)
        let b = fuzzer.makeBuilder()

        // Insert another sample that has a typegroup into the corpus
        b.wasmDefineTypeGroup(recursiveGenerator: {
            b.wasmDefineArrayType(elementType: .wasmi64, mutability: true)
        })

        fuzzer.corpus.add(b.finalize(), ProgramAspects(outcome: .succeeded))

        // Now try the splice mutator

        b.wasmDefineTypeGroup(recursiveGenerator: {
            b.wasmDefineArrayType(elementType: .wasmi32, mutability: true)
        })

        let prog = b.finalize()

        let originalEndTypeGroupInstructions = prog.code.filter { instr in
            instr.op is WasmEndTypeGroup
        }

        XCTAssertEqual(originalEndTypeGroupInstructions.count, 1)
        XCTAssertEqual(originalEndTypeGroupInstructions[0].numInputs, 1)

        let spliceMutator = SpliceMutator()

        let candidates = prog.code.filter { instr in spliceMutator.canMutate(instr) == true }
        XCTAssertEqual(candidates.count, 1)

        let mutatedProg = spliceMutator.mutate(prog, using: b, for: fuzzer)!

        let newEndTypeGroupInstructions = mutatedProg.code.filter { instr in
            instr.op is WasmEndTypeGroup
        }

        XCTAssertEqual(newEndTypeGroupInstructions.count, 1)
        XCTAssertGreaterThan(newEndTypeGroupInstructions[0].numInputs, 1)
    }

    func testCodeGenMutatorWasmTypeGroups() {
        let env = JavaScriptEnvironment()
        let config = Configuration(logLevel: .error)
        let fuzzer = makeMockFuzzer(config: config, environment: env)
        let b = fuzzer.makeBuilder()

        // We need a minimum number of visible variables for codeGeneration.
        b.loadInt(1)
        b.loadInt(2)

        b.wasmDefineTypeGroup(recursiveGenerator: {
            b.wasmDefineArrayType(elementType: .wasmi32, mutability: true)
        })

        let prog = b.finalize()

        let originalEndTypeGroupInstructions = prog.code.filter { instr in
            instr.op is WasmEndTypeGroup
        }

        XCTAssertEqual(originalEndTypeGroupInstructions.count, 1)
        XCTAssertEqual(originalEndTypeGroupInstructions[0].numInputs, 1)

        let codeGenMutator = CodeGenMutator()

        let candidates = prog.code.filter { instr in codeGenMutator.canMutate(instr) == true }
        XCTAssertEqual(candidates.count, 1)

        let mutatedProg = codeGenMutator.mutate(prog, using: b, for: fuzzer)!

        let newEndTypeGroupInstructions = mutatedProg.code.filter { instr in
            instr.op is WasmEndTypeGroup
        }

        XCTAssertEqual(newEndTypeGroupInstructions.count, 1)
        XCTAssertGreaterThan(newEndTypeGroupInstructions[0].numInputs, 1)
    }

    func testCodeGenMutatorNamedStrings() {
        // A generator that deterministically generates a different value each time.
        var called = false
        func generateString() -> String {
            if called {
                return "newValue"
            } else {
                called = true
                return "originalValue"
            }
        }
        let mockNamedString = ILType.namedString(ofName: "NamedString")

        let env = JavaScriptEnvironment()
        env.addNamedStringGenerator(forType: mockNamedString, with: generateString)

        let config = Configuration(logLevel: .error)
        let fuzzer = makeMockFuzzer(config: config, environment: env)
        let b = fuzzer.makeBuilder()

        // We need a minimum number of visible variables for codeGeneration.
        b.loadInt(1)
        b.loadInt(2)

        let _ = b.findOrGenerateType(mockNamedString)
        XCTAssert(called)

        let prog = b.finalize()

        let originalLoadInstruction = prog.code.filter { instr in
            instr.op is LoadString
        }

        XCTAssertEqual(originalLoadInstruction.count, 1)
        let originalLoad = originalLoadInstruction[0].op as! LoadString
        XCTAssertEqual(originalLoad.value, "originalValue")

        // Mutator is probabalistic, try 10 times to ensure we are very likely
        // to hit the generateString call.
        let mutator = OperationMutator()
        for _ in 1...10 {
            let newBuilder = fuzzer.makeBuilder()
            newBuilder.adopting {
                mutator.mutate(originalLoadInstruction[0], newBuilder)
            }

            let mutatedProg = newBuilder.finalize()

            let newLoadInstruction = mutatedProg.code.filter { instr in
                instr.op is LoadString
            }

            XCTAssertEqual(newLoadInstruction.count, 1)
            let newLoad = newLoadInstruction[0].op as! LoadString
            if newLoad.value == "newValue" {
                return
            }
        }
        XCTFail("Mutator ran 10 times without rerunning custom string generator")
    }

    func testConcatMutatorBundleHostWithBundleCorpus() {
        let env = JavaScriptEnvironment()
        let config = Configuration(logLevel: .error, generateBundle: true)
        let fuzzer = makeMockFuzzer(config: config, environment: env)

        do {
            let b = fuzzer.makeBuilder()
            b.emit(BeginBundleScript())
            b.callFunction(
                b.createNamedVariable(forBuiltin: "print"), withArgs: [b.loadString("corpus")])
            b.emit(EndBundleScript())
            fuzzer.corpus.add(b.finalize(), ProgramAspects(outcome: .succeeded))
        }

        let mutator = ConcatMutator()
        var hostBundle: Program? = nil
        do {
            let b = fuzzer.makeBuilder()
            b.emit(BeginBundleScript())
            b.callFunction(
                b.createNamedVariable(forBuiltin: "print"), withArgs: [b.loadString("host")])
            b.emit(EndBundleScript())
            hostBundle = b.finalize()
        }
        let builder = fuzzer.makeBuilder()
        let mutated = mutator.mutate(hostBundle!, using: builder, for: fuzzer)!

        XCTAssertTrue(mutated.code.isBundle)
        XCTAssertTrue(mutated.code.isStaticallyValid())
        let actual = fuzzer.lifter.lift(mutated)
        let expected = """
            // JS_BUNDLE_SCRIPT
            print("host");
            // JS_BUNDLE_SCRIPT
            print("corpus");

            """
        XCTAssertEqual(actual, expected)
    }

    func testConcatMutatorNonBundleHostWithNonBundleCorpus() {
        let env = JavaScriptEnvironment()
        let config = Configuration(logLevel: .error, generateBundle: true)
        let fuzzer = makeMockFuzzer(config: config, environment: env)

        let b = ProgramBuilder(for: fuzzer, parent: nil, isBundle: false)
        b.callFunction(
            b.createNamedVariable(forBuiltin: "print"), withArgs: [b.loadString("corpus")])
        fuzzer.corpus.add(b.finalize(), ProgramAspects(outcome: .succeeded))

        let mutator = ConcatMutator()

        let b2 = ProgramBuilder(for: fuzzer, parent: nil, isBundle: false)
        b2.callFunction(
            b2.createNamedVariable(forBuiltin: "print"), withArgs: [b2.loadString("host")])
        let hostNonBundle = b2.finalize()

        let builder = ProgramBuilder(for: fuzzer, parent: nil, isBundle: false)
        let mutated = mutator.mutate(hostNonBundle, using: builder, for: fuzzer)!

        XCTAssertFalse(mutated.code.isBundle)
        XCTAssertTrue(mutated.code.isStaticallyValid())
        let actual = fuzzer.lifter.lift(mutated)
        let expected = """
            print("host");
            print("corpus");

            """
        XCTAssertEqual(actual, expected)
    }

    func testSpliceMutatorBundleHostWithBundleCorpus() {
        let env = JavaScriptEnvironment()
        let config = Configuration(logLevel: .error, generateBundle: true)
        let fuzzer = makeMockFuzzer(config: config, environment: env)

        let b = fuzzer.makeBuilder()
        b.emit(BeginBundleScript())
        b.callFunction(
            b.createNamedVariable(forBuiltin: "print"), withArgs: [b.loadString("corpus")])
        b.emit(EndBundleScript())
        fuzzer.corpus.add(b.finalize(), ProgramAspects(outcome: .succeeded))

        let mutator = SpliceMutator()

        let b2 = fuzzer.makeBuilder()
        b2.emit(BeginBundleScript())
        b2.callFunction(
            b2.createNamedVariable(forBuiltin: "print"), withArgs: [b2.loadString("host")])
        b2.emit(EndBundleScript())
        let hostBundle = b2.finalize()

        let builder = fuzzer.makeBuilder()
        let mutated = mutator.mutate(hostBundle, using: builder, for: fuzzer)!

        XCTAssertTrue(mutated.code.isBundle)
        XCTAssertTrue(mutated.code.isStaticallyValid())
        let actual = fuzzer.lifter.lift(mutated)

        // Splicing is not deterministic, so we cannot assert the exact output.
        XCTAssertTrue(actual.contains("corpus"))
        XCTAssertTrue(actual.contains("host"))
        XCTAssertTrue(actual.contains("// JS_BUNDLE_SCRIPT"))
    }

    func testSpliceMutatorNonBundleHostWithNonBundleCorpus() {
        let env = JavaScriptEnvironment()
        let config = Configuration(logLevel: .error, generateBundle: true)
        let fuzzer = makeMockFuzzer(config: config, environment: env)

        let b = ProgramBuilder(for: fuzzer, parent: nil, isBundle: false)
        b.callFunction(
            b.createNamedVariable(forBuiltin: "print"), withArgs: [b.loadString("corpus")])
        fuzzer.corpus.add(b.finalize(), ProgramAspects(outcome: .succeeded))

        let mutator = SpliceMutator()

        let b2 = ProgramBuilder(for: fuzzer, parent: nil, isBundle: false)
        b2.callFunction(
            b2.createNamedVariable(forBuiltin: "print"), withArgs: [b2.loadString("host")])
        let hostNonBundle = b2.finalize()

        let builder = ProgramBuilder(for: fuzzer, parent: nil, isBundle: false)
        let mutated = mutator.mutate(hostNonBundle, using: builder, for: fuzzer)!

        XCTAssertFalse(mutated.code.isBundle)
        XCTAssertTrue(mutated.code.isStaticallyValid())
        let actual = fuzzer.lifter.lift(mutated)

        // Splicing is not deterministic, so we cannot assert the exact output.
        XCTAssertTrue(actual.contains("corpus"))
        XCTAssertTrue(actual.contains("host"))
        XCTAssertFalse(actual.contains("// JS_BUNDLE"))
    }

    func testCombineMutatorNonBundle() {
        let env = JavaScriptEnvironment()
        let config = Configuration(logLevel: .error)
        let fuzzer = makeMockFuzzer(config: config, environment: env)

        // Corpus program:
        let b = ProgramBuilder(for: fuzzer, parent: nil, isBundle: false)
        b.callFunction(
            b.createNamedVariable(forBuiltin: "print"), withArgs: [b.loadString("corpus start")])
        b.callFunction(
            b.createNamedVariable(forBuiltin: "print"), withArgs: [b.loadString("corpus end")])
        fuzzer.corpus.add(b.finalize(), ProgramAspects(outcome: .succeeded))

        let mutator = CombineMutator()

        // Host program:
        let b2 = ProgramBuilder(for: fuzzer, parent: nil, isBundle: false)
        b2.callFunction(
            b2.createNamedVariable(forBuiltin: "print"), withArgs: [b2.loadString("host start")])
        b2.callFunction(
            b2.createNamedVariable(forBuiltin: "print"), withArgs: [b2.loadString("host end")])
        let hostProg = b2.finalize()

        let builder = ProgramBuilder(for: fuzzer, parent: nil, isBundle: false)
        let mutated = mutator.mutate(hostProg, using: builder, for: fuzzer)!

        XCTAssertFalse(mutated.code.isBundle)
        XCTAssertTrue(mutated.code.isStaticallyValid())
        let actual = fuzzer.lifter.lift(mutated)

        let expectedPattern1 = """
            print("corpus start");
            print("corpus end");
            print("host start");
            print("host end");

            """

        let expectedPattern2 = """
            print("host start");
            print("host end");
            print("corpus start");
            print("corpus end");

            """
        let expectedPattern3 = """
            print("host start");
            print("corpus start");
            print("corpus end");
            print("host end");

            """

        XCTAssertTrue(
            actual == expectedPattern1 || actual == expectedPattern2 || actual == expectedPattern3,
            "Output does not match expected patterns. Actual:\n\(actual)")
    }

    func testCombineMutatorBundle() {
        let env = JavaScriptEnvironment()
        let config = Configuration(logLevel: .error, generateBundle: true)
        let fuzzer = makeMockFuzzer(config: config, environment: env)

        // Corpus: a bundle script
        let b = fuzzer.makeBuilder()
        b.emit(BeginBundleScript())
        b.callFunction(
            b.createNamedVariable(forBuiltin: "print"), withArgs: [b.loadString("corpus start")])
        b.callFunction(
            b.createNamedVariable(forBuiltin: "print"), withArgs: [b.loadString("corpus end")])
        b.emit(EndBundleScript())
        fuzzer.corpus.add(b.finalize(), ProgramAspects(outcome: .succeeded))

        let mutator = CombineMutator()

        // Host: two bundle scripts
        let b2 = fuzzer.makeBuilder()
        b2.emit(BeginBundleScript())
        b2.callFunction(
            b2.createNamedVariable(forBuiltin: "print"), withArgs: [b2.loadString("host1 start")])
        b2.callFunction(
            b2.createNamedVariable(forBuiltin: "print"), withArgs: [b2.loadString("host1 end")])
        b2.emit(EndBundleScript())

        b2.emit(BeginBundleScript())
        b2.callFunction(
            b2.createNamedVariable(forBuiltin: "print"), withArgs: [b2.loadString("host2 start")])
        b2.callFunction(
            b2.createNamedVariable(forBuiltin: "print"), withArgs: [b2.loadString("host2 end")])
        b2.emit(EndBundleScript())
        let hostBundle = b2.finalize()

        let builder = fuzzer.makeBuilder()
        let mutated = mutator.mutate(hostBundle, using: builder, for: fuzzer)!

        XCTAssertTrue(mutated.code.isBundle)
        XCTAssertTrue(mutated.code.isStaticallyValid())
        let actual = fuzzer.lifter.lift(mutated)

        // The mutation can happen at the first EndBundleScript or the second EndBundleScript.
        // "corpus" should be either between host1 and host2, or after host2.
        let expectedPattern1 = """
            // JS_BUNDLE_SCRIPT
            print("host1 start");
            print("host1 end");
            // JS_BUNDLE_SCRIPT
            print("corpus start");
            print("corpus end");
            // JS_BUNDLE_SCRIPT
            print("host2 start");
            print("host2 end");

            """
        let expectedPattern2 = """
            // JS_BUNDLE_SCRIPT
            print("host1 start");
            print("host1 end");
            // JS_BUNDLE_SCRIPT
            print("host2 start");
            print("host2 end");
            // JS_BUNDLE_SCRIPT
            print("corpus start");
            print("corpus end");

            """

        XCTAssertTrue(
            actual == expectedPattern1 || actual == expectedPattern2,
            "Output does not match expected patterns. Actual:\n\(actual)")
    }

    func testWasmArrayNewFixedExtension() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.loadInt(1)  // dummy prefix

        let arrayDef = b.wasmDefineTypeGroup {
            return [b.wasmDefineArrayType(elementType: ILType.wasmi32, mutability: true)]
        }[0]
        b.buildWasmModule { module in
            module.addWasmFunction(with: [] => []) { fn, label, params in
                let i1 = fn.consti32(1)
                let array = fn.wasmArrayNewFixed(arrayType: arrayDef, elements: [i1])
                fn.wasmArrayGet(array: array, index: fn.consti32(0))
                return []
            }
        }

        let prog = b.finalize()
        let instr = prog.code.filter { $0.op is WasmArrayNewFixed }[0]
        XCTAssertEqual((instr.op as! WasmArrayNewFixed).size, 1)

        let mutator = OperationMutator()
        let newBuilder = fuzzer.makeBuilder()

        newBuilder.adopting {
            for i in 0..<instr.index {
                newBuilder.adopt(prog.code[i])
            }
            mutator.mutate(instr, newBuilder)
            for i in (instr.index + 1)..<prog.code.count {
                newBuilder.adopt(prog.code[i])
            }
        }

        let mutatedProg = newBuilder.finalize()
        let mutatedInstr = mutatedProg.code.first(where: { $0.op is WasmArrayNewFixed })!
        let newOp = mutatedInstr.op as! WasmArrayNewFixed
        XCTAssertGreaterThan(newOp.size, 1)
    }

    func testWasmArrayNewFixedMutationGeneratesNewVariable() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        // Dummy prefix to pass `hasVisibleJsVariables()` check in `extendVariadicOperationByOneInput()`
        b.loadInt(1)

        let arrayDef = b.wasmDefineTypeGroup {
            return [b.wasmDefineArrayType(elementType: ILType.wasmi64, mutability: true)]
        }[0]

        b.buildWasmModule { module in
            module.addWasmFunction(with: [] => []) { fn, label, params in
                fn.wasmArrayNewFixed(arrayType: arrayDef, elements: [])
                return []
            }
        }

        let prog = b.finalize()
        let instr = prog.code.first(where: { $0.op is WasmArrayNewFixed })!
        let mutator = OperationMutator()

        b.adopting {
            for i in 0..<instr.index {
                b.adopt(prog.code[i])
            }
            mutator.mutate(instr, b)
            for i in (instr.index + 1)..<prog.code.count {
                b.adopt(prog.code[i])
            }
        }

        let mutatedProg = b.finalize()
        let actual = FuzzILLifter().lift(mutatedProg)
        let expectedPattern = #"""
                    v5 <- .+
                    v6 <- WasmArrayNewFixed \[v2(, v5)+\]
            """#

        XCTAssertNotNil(
            actual.range(of: expectedPattern, options: .regularExpression),
            "Lifted program did not match expected pattern. Actual:\n\(actual)")
    }
}
