// Copyright 2023 Google LLC
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


// A post-processor that inserts calls to the sandbox corruption functions (defined in the codeSuffix below) into the generated samples.
fileprivate struct SandboxFuzzingPostProcessor: FuzzingPostProcessor {
    func process(_ program: Program, for fuzzer: Fuzzer) throws -> Program {
        // We don't instrument every generated program since we still want the fuzzer to make progress towards
        // discovering more interestesting programs and adding them to the corpus. Corrupting objects in every
        // generated program might hamper that.
        if probability(0.5) { return program }

        let b = fuzzer.makeBuilder(forMutating: program)

        enum TraversalStep: Int {
            case neighbor = 0
            case pointer = 1
        }

        func corruptSomething() {
            // TODO: Currently, Fuzzilli wraps sandbox corruptions inside `b.eval(...)`. Because Fuzzilli treats `eval` strings as opaque, the mutation engine cannot genetically evolve the `pathArray` tuples or seeds. Implementing native Instruction classes (e.g. `.corruptDataWithBitflip(...)`) would allow Fuzzilli to structurally mutate these corruption paths.
            // Make sure that we get a JS variable that is not a primitive.
            guard let target = b.findVariable(satisfying: { v in
                !b.type(of: v).Is(.primitive) && b.type(of: v).Is(.jsAnything)
            }) else { return }
            let numCorruptions = Int.random(in: 1...3)
            for _ in 0..<numCorruptions {
                // The traversal path is an array of tuples: [Step, Value]
                // If Step == .neighbor (0), Value is the exact 16-bit hash query.
                // If Step == .pointer (1), Value is a UInt32 seed used by JS to calculate the pointer offset.
                let depth = Int.random(in: 0..<10)
                let pathTuples = (0..<depth).map { _ -> String in
                    if probability(0.25) {
                        let hashQuery = Int.random(in: 0...0xffff)
                        return "[\(TraversalStep.neighbor.rawValue), \(hashQuery)]"
                    } else {
                        let offsetSeed = UInt32.random(in: 0...UInt32.max)
                        return "[\(TraversalStep.pointer.rawValue), \(offsetSeed)]"
                    }
                }.joined(separator: ", ")
                let pathArray = "[\(pathTuples)]"

                let size = chooseUniform(from: [8, 16, 32])
                let offsetSeed = UInt32.random(in: 0...UInt32.max)

                let subFieldOffset = switch size {
                    case 8: Int.random(in: 0..<4)
                    case 16: Int.random(in: 0..<2) * 2
                    default: 0
                }

                let command: String
                switch Double.random(in: 0..<1) {
                case 0.80..<0.90:
                    let bitPosition = Int.random(in: 0..<size)
                    command = "corruptWithWorker(%@, \(pathArray), \(offsetSeed), \(size), \(subFieldOffset), \(bitPosition))"
                case 0.90..<1.0:
                    // TODO: We could make more use of our typer information and use this more directly (without traversal) on objects that we know are functions.
                    let builtinSeed = UInt32.random(in: 0...UInt32.max)
                    command = "corruptFunction(%@, \(pathArray), \(builtinSeed))"
                default:
                    let bitPosition = Int.random(in: 0..<size)

                    let magnitude = Int.random(in: 0...size)
                    let upper: UInt64 = 1 << magnitude
                    let lower: UInt64 = upper >> 1
                    let randomMagnitudeValue = lower == upper ? lower : UInt64.random(in: lower..<upper)

                    let incrementValue = randomMagnitudeValue == 0 ? 1 : randomMagnitudeValue

                    command = chooseUniform(from: [
                        "corruptDataWithBitflip(%@, \(pathArray), \(offsetSeed), \(size), \(subFieldOffset), \(bitPosition))",
                        "corruptDataWithIncrement(%@, \(pathArray), \(offsetSeed), \(size), \(subFieldOffset), \(incrementValue)n)",
                        "corruptDataWithReplace(%@, \(pathArray), \(offsetSeed), \(size), \(subFieldOffset), \(randomMagnitudeValue)n)"
                    ])
                }

                b.eval(command, with: [target])
            }
        }

        b.adopting() {
            for instr in program.code {
                b.adopt(instr)

                if b.context.contains(.javascript) && probability(0.1) {
                    corruptSomething()
                }
            }
        }

        return b.finalize()
    }
}

let BytecodeFuzzer = ProgramTemplate("BytecodeFuzzer") { b in
    b.buildPrefix()

    // Generate some random code to produce some values
    b.build(n: 10)

    // Create a random function
    let f = b.buildPlainFunction(with: b.randomParameters()) { args in
        b.build(n: 25)
    }

    // Invoke the function once to trigger bytecode compilation
    b.callFunction(f, withArgs: b.randomArguments(forCalling: f))

    // Get the Bytecode object
    let bytecodeObj = b.eval("%GetBytecode(%@)", with: [f], hasOutput: true)!

    // Wrap the bytecode in a Uint8Array
    let bytecode = b.getProperty("bytecode", of: bytecodeObj)
    let Uint8Array = b.createNamedVariable(forBuiltin: "Uint8Array")
    let u8 = b.construct(Uint8Array, withArgs: [bytecode])

    // Mutate the bytecode
    let numMutations = Int.random(in: 1...3)
    for _ in 0..<numMutations {
        let index = Int64.random(in: 0..<200)
        let newByte: Variable
        if probability(0.5) {
            let bit = b.loadInt(1 << Int.random(in: 0..<8))
            let oldByte = b.getElement(index, of: u8)
            newByte = b.binary(oldByte, bit, with: .Xor)
        } else {
            newByte = b.loadInt(Int64.random(in: 0..<256))
        }
        b.setElement(index, of: u8, to: newByte)
    }

    // Install the mutated bytecode
    b.eval("%InstallBytecode(%@, %@)", with: [f, bytecodeObj])

    // Execute the new bytecode
    b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
}

let v8SandboxProfile = Profile(
    processArgs: { randomize in
        v8ProcessArgs(randomize: randomize, forSandbox: true)
    },

    processArgsReference: nil,

    // ASan options.
    // - abort_on_error=true: We need asan to exit in a way that's detectable for Fuzzilli as a crash
    // - handle_sigill=true: It seems by default ASAN doesn't handle SIGILL, but we want that to have stack traces
    // - symbolize=false: Symbolization can tak a _very_ long time (> 1s), which may cause crashing samples to time out before the stack trace has been captured (in which case Fuzzilli will discard the sample)
    // - redzone=128: This value is used by Clusterfuzz for reproducing testcases so we should use the same value
    processEnv: ["ASAN_OPTIONS" : "abort_on_error=1:handle_sigill=1:symbolize=false:redzone=128", "UBSAN_OPTIONS" : "abort_on_error=1:symbolize=false:redzone=128"],

    maxExecsBeforeRespawn: 1000,

    // ASan builds are slower, so we use a larger timeout.
    timeout: Timeout.interval(500, 1200),

    codePrefix: """
                //
                // BEGIN FUZZER GENERATED CODE
                //

                """,

    codeSuffix: """

                //
                // BEGIN FUZZER HELPER CODE
                //

                // The following functions corrupt a given object in a deterministic fashion (based on the provided seed and path) and log the steps being performed.

                function getSandboxCorruptionHelpers() {
                    // In general, memory contents are represented as (unsigned) BigInts, everything else (addresses, offsets, etc.) are Numbers.

                    function assert(c) {
                        if (!c) {
                            throw new Error("Assertion in the in-sandbox-corruption API failed!");
                        }
                    }

                    const kHeapObjectTag = 0x1n;
                    // V8 uses the two lowest bits as tag bits: 0x1 to indicate HeapObject vs Smi and 0x2 to indicate a weak reference.
                    const kHeapObjectTagMask = 0x3n;
                    // Offsets should be a multiple of 4, as that's the typical field size.
                    const kOffsetAlignmentMask = ~0x3;

                    const builtins = Sandbox.getBuiltinNames();
                    assert(builtins.length > 0);

                    const Step = {
                        NEIGHBOR: 0,
                        POINTER: 1,
                    };

                    // Helper class for accessing in-sandbox memory.
                    class Memory {
                        constructor() {
                            let buffer = new Sandbox.MemoryView(0, 0x100000000);
                            this.dataView = new DataView(buffer);
                            this.taggedView = new Uint32Array(buffer);
                        }

                        read(addr, numBits) {
                            switch (numBits) {
                                case 8: return BigInt(this.dataView.getUint8(addr));
                                case 16: return BigInt(this.dataView.getUint16(addr, true));
                                case 32: return BigInt(this.dataView.getUint32(addr, true));
                            }
                        }

                        write(addr, value, numBits) {
                            switch (numBits) {
                                case 8: this.dataView.setUint8(addr, Number(value)); break;
                                case 16: this.dataView.setUint16(addr, Number(value), true); break;
                                case 32: this.dataView.setUint32(addr, Number(value), true); break;
                            }
                        }

                        copyTagged(source, destination, size) {
                            assert(size % 4 == 0);
                            let toIndex = destination / 4;
                            let startIndex = source / 4;
                            let endIndex = (source + size) / 4;
                            this.taggedView.copyWithin(toIndex, startIndex, endIndex);
                        }
                    }
                    let memory = new Memory;

                    // A worker thread that corrupts memory from the background.
                    //
                    // The main thread can post messages to this worker which contain
                    // effectively (address, valueA, valueB) triples. This worker
                    // will then permanently flip all the given addresses between
                    // valueA and valueB. This for example makes it possible to find
                    // double-fetch issues and similar bugs.
                    function workerFunc() {
                        let memory = new DataView(new Sandbox.MemoryView(0, 0x100000000));
                        let work = [];
                        let iteration = 0;

                        onmessage = function(e) {
                            if (work.length == 0) {
                                // Time to start working.
                                setTimeout(doWork);
                            }
                            work.push(e.data);
                        }

                        function corrupt(address, value, size) {
                            switch (size) {
                                case 8:
                                    memory.setUint8(address, value);
                                    break;
                                case 16:
                                    memory.setUint16(address, value, true);
                                    break;
                                case 32:
                                    memory.setUint32(address, value, true);
                                    break;
                            }
                        }

                        function doWork() {
                            iteration++;
                            for (let item of work) {
                                let value = (iteration % 2) == 0 ? item.valueA : item.valueB;
                                corrupt(item.address, value, item.size);
                            }
                            // Schedule the next round of work.
                            setTimeout(doWork);
                        }
                    }
                    if (typeof globalThis.memory_corruption_worker === 'undefined') {
                        // Define as non-configurable and non-enumerable property.
                        let worker = new Worker(workerFunc, {type: 'function'});
                        Object.defineProperty(globalThis, 'memory_corruption_worker', {value: worker});
                    }


                    // Helper function to deterministically find a random neighbor object.
                    //
                    // This logic is designed to deal with a (somewhat) non-deterministic heap layout to ensure that test cases are reproducible.
                    // In practice, it should most of the time find the same neighbor object if (a) that object is always allocated after the
                    // start object, (b) is within the first N (currently 100) objects, and (c) is always the first neighbor of its instance type.
                    //
                    // This is achieved by iterating over the heap starting from the start object and computing a simple 16-bit hash value for each
                    // object. At the end, we select the first object whose hash is closest to a random 16-bit hash query.
                    // Note that we always take the first object if there are multiple objects with the same instance type.
                    // For finding later neighbors, we rely on the traversal path containing multiple Step.NEIGHBOR entries.
                    function findRandomNeighborObject(addr, hashQuery) {
                        const N = 100;
                        const kUint16Max = 0xffff;
                        const kUnknownInstanceId = kUint16Max;

                        // Simple hash function for 16-bit unsigned integers. See https://github.com/skeeto/hash-prospector
                        function hash16(x) {
                            assert(x >= 0 && x <= kUint16Max);
                            x ^= x >> 8;
                            x = (x * 0x88B5) & 0xffff;
                            x ^= x >> 7;
                            x = (x * 0xdB2d) & 0xffff;
                            x ^= x >> 9;
                            return x;
                        }

                        hashQuery = hashQuery & 0xffff;
                        let currentWinner = addr;
                        let currentBest = kUint16Max;

                        for (let i = 0; i < N; i++) {
                            addr += Sandbox.getSizeOfObjectAt(addr);
                            let typeId = Sandbox.getInstanceTypeIdOfObjectAt(addr);
                            if (typeId == kUnknownInstanceId) {
                                break;
                            }
                            let hash = hash16(typeId);
                            let score = Math.abs(hash - hashQuery);
                            if (score < currentBest) {
                                currentBest = score;
                                currentWinner = addr;
                            }
                        }

                        return currentWinner;
                    }

                    // Helper function to create a copy of the object at the given address and return the address of the copy.
                    // This is for example useful when we would like to corrupt a read-only object: in that case, we can then instead
                    // create a copy of the read-only object, install that into whichever object references is, then corrupt the copy.
                    function copyObjectAt(source) {
                        let objectSize = Sandbox.getSizeOfObjectAt(source);
                        // Simple way to get a placeholder object that's large enough: create a sequential string.
                        // TODO(saelo): maybe add a method to the sandbox api to construct an object of the appropriate size.
                        let placeholder = Array(objectSize).fill("a").join("");
                        let destination = Sandbox.getAddressOf(placeholder);
                        memory.copyTagged(source, destination, objectSize);
                        return destination;
                    }

                    function getRandomAlignedOffset(addr, offsetSeed) {
                        let objectSize = Sandbox.getSizeOfObjectAt(addr);
                        return (offsetSeed % objectSize) & kOffsetAlignmentMask;
                    }

                    function getBaseAddress(obj) {
                        try {
                            if (!Sandbox.isWritable(obj)) return null;
                            return Sandbox.getAddressOf(obj);
                        } catch (e) {
                            // Presumably, |obj| is a Smi, not a HeapObject.
                            return null;
                        }
                    }

                    function prepareDataCorruptionContext(obj, path, offsetSeed, numBitsToCorrupt, subFieldOffset) {
                        let baseAddr = getBaseAddress(obj);
                        if (!baseAddr) return null;

                        let addr = evaluateTraversalPath(baseAddr, path);
                        if (!addr) return null;

                        let offset = getRandomAlignedOffset(addr, offsetSeed);
                        offset += subFieldOffset;

                        let oldValue = memory.read(addr + offset, numBitsToCorrupt);
                        return { addr, offset, oldValue, finalizeDataCorruption };
                    }

                    function finalizeDataCorruption(addr, offset, oldValue, newValue, numBitsToCorrupt, typeString) {
                        assert(oldValue >= 0 && oldValue < (1n << BigInt(numBitsToCorrupt)));
                        assert(newValue >= 0 && newValue < (1n << BigInt(numBitsToCorrupt)));

                        memory.write(addr + offset, newValue, numBitsToCorrupt);
                        print("  Corrupted " + numBitsToCorrupt + "-bit field (" + typeString + ") at offset " + offset + ". Old value: 0x" + oldValue.toString(16) + ", new value: 0x" + newValue.toString(16));
                    }

                    // The path argument is an array of [Step, Value] tuples.
                    // If Step === Step.NEIGHBOR, Value is the exact 16-bit hash query.
                    // If Step === Step.POINTER, Value is a random UInt32 seed used to calculate an aligned offset.
                    function evaluateTraversalPath(addr, path) {
                        let instanceType = Sandbox.getInstanceTypeOfObjectAt(addr);
                        print("Corrupting memory starting from object at 0x" + addr.toString(16) + " of type " + instanceType);

                        for (let [stepType, seedValue] of path) {
                            if (!Sandbox.isWritableObjectAt(addr)) {
                                print("  Not corrupting read-only object. Bailing out.");
                                return null;
                            }

                            switch (stepType) {
                                case Step.NEIGHBOR: {
                                    let oldAddr = addr;
                                    addr = findRandomNeighborObject(addr, seedValue);
                                    print("  Jumping to neighboring object at offset " + (addr - oldAddr));
                                    break;
                                }
                                case Step.POINTER: {
                                    let offset = getRandomAlignedOffset(addr, seedValue);
                                    let oldValue = memory.read(addr + offset, 32);

                                    // If the selected offset doesn't contain a valid pointer, we break out
                                    // of the traversal loop but still corrupt the current (valid) object.
                                    let isLikelyPointer = (oldValue & kHeapObjectTag) == kHeapObjectTag;
                                    if (!isLikelyPointer) {
                                        break;
                                    }

                                    let newAddr = Number(oldValue & ~kHeapObjectTagMask);
                                    if (!Sandbox.isValidObjectAt(newAddr)) {
                                        break;
                                    }

                                    print("  Following pointer at offset " + offset + " to object at 0x" + newAddr.toString(16));

                                    if (!Sandbox.isWritableObjectAt(newAddr)) {
                                        newAddr = copyObjectAt(newAddr);
                                        memory.write(addr + offset, BigInt(newAddr) | kHeapObjectTag, 32);
                                        print("  Referenced object is in read-only memory. Created and linked a writable copy at 0x" + newAddr.toString(16));
                                    }
                                    addr = newAddr;
                                    break;
                                }
                            }
                        }
                        return Sandbox.isWritableObjectAt(addr) ? addr : null;
                    }

                    return {
                        builtins, getBaseAddress, evaluateTraversalPath, prepareDataCorruptionContext
                    };
                }

                function corruptDataWithBitflip(obj, path, offsetSeed, numBitsToCorrupt, subFieldOffset, bitPosition) {
                    let { addr, offset, oldValue, finalizeDataCorruption } = getSandboxCorruptionHelpers().prepareDataCorruptionContext(obj, path, offsetSeed, numBitsToCorrupt, subFieldOffset) || {};
                    if (!addr) return;

                    let newValue = oldValue ^ (1n << BigInt(bitPosition));
                    finalizeDataCorruption(addr, offset, oldValue, newValue, numBitsToCorrupt, "Bitflip");
                }

                function corruptDataWithIncrement(obj, path, offsetSeed, numBitsToCorrupt, subFieldOffset, incrementValue) {
                    let { addr, offset, oldValue, finalizeDataCorruption } = getSandboxCorruptionHelpers().prepareDataCorruptionContext(obj, path, offsetSeed, numBitsToCorrupt, subFieldOffset) || {};
                    if (!addr) return;

                    let newValue = (oldValue + incrementValue) & ((1n << BigInt(numBitsToCorrupt)) - 1n);
                    finalizeDataCorruption(addr, offset, oldValue, newValue, numBitsToCorrupt, "Increment");
                }

                function corruptDataWithReplace(obj, path, offsetSeed, numBitsToCorrupt, subFieldOffset, replaceValue) {
                    let { addr, offset, oldValue, finalizeDataCorruption } = getSandboxCorruptionHelpers().prepareDataCorruptionContext(obj, path, offsetSeed, numBitsToCorrupt, subFieldOffset) || {};
                    if (!addr) return;

                    let newValue = replaceValue;
                    finalizeDataCorruption(addr, offset, oldValue, newValue, numBitsToCorrupt, "Replace");
                }

                function corruptWithWorker(obj, path, offsetSeed, numBitsToCorrupt, subFieldOffset, bitPosition) {
                    let { addr, offset, oldValue } = getSandboxCorruptionHelpers().prepareDataCorruptionContext(obj, path, offsetSeed, numBitsToCorrupt, subFieldOffset) || {};
                    if (!addr) return;

                    let newValue = oldValue ^ (1n << BigInt(bitPosition));

                    globalThis.memory_corruption_worker.postMessage({
                        address: addr + offset, valueA: Number(oldValue), valueB: Number(newValue), size: numBitsToCorrupt
                    });

                    print("  Started background worker to continuously flip " + numBitsToCorrupt + "-bit field at offset " + offset + " between 0x" + oldValue.toString(16) + " and 0x" + newValue.toString(16));
                }

                function corruptFunction(obj, path, builtinSeed) {
                    let { builtins, getBaseAddress, evaluateTraversalPath } = getSandboxCorruptionHelpers();
                    let baseAddr = getBaseAddress(obj);
                    if (!baseAddr) return;
                    let addr = evaluateTraversalPath(baseAddr, path);
                    if (!addr) return;

                    let instanceTypeId = Sandbox.getInstanceTypeIdOfObjectAt(addr);
                    if (instanceTypeId === Sandbox.getInstanceTypeIdFor("JS_FUNCTION_TYPE")) {
                        let targetObj = Sandbox.getObjectAt(addr);
                        let builtinId = builtinSeed % builtins.length;
                        try {
                            Sandbox.setFunctionCodeToBuiltin(targetObj, builtinId);
                            print("  Hijacked JSFunction code pointer! Swapped with builtin: " + builtins[builtinId]);
                        } catch(e) {}
                    }
                }
                """,

    ecmaVersion: ECMAScriptVersion.es6,

    startupTests: [
        // This makes sure that the fuzzilli builtin exists.
        ("fuzzilli('FUZZILLI_PRINT', 'test')", .shouldSucceed),
        // This makes sure that the memory corruption api is available.
        ("Sandbox.getAddressOf([1, 2, 3])", .shouldSucceed),
        // This makes sure that the corruption functions are available and working. It should not corrupt anything as it's passed an object in read-only space ('undefined').
        // TODO: Adding tests that stress the pathArray traversal logic could be beneficial.
        ("corruptDataWithBitflip(undefined, [], 0, 8, 0, 0);", .shouldSucceed),
        ("corruptDataWithIncrement(42, [], 0, 8, 0, 0n);", .shouldSucceed),
        ("corruptDataWithReplace('test', [], 0, 8, 0, 0n);", .shouldSucceed),
        ("corruptWithWorker(Symbol('test'), [], 0, 8, 0, 0);", .shouldSucceed),
        // We cannot pass a real function here because `Sandbox.setFunctionCodeToBuiltin` will abort the process if the chosen builtin's parameter count doesn't match the target function.
        ("corruptFunction(undefined, [], 0);", .shouldSucceed),
        // This triggers a DCHECK failure, which should be ignored, and execution should continue.
        ("fuzzilli('FUZZILLI_CRASH', 2)", .shouldSucceed),
        // This checks that we do not have DEBUG defined, and execution should continue.
        ("fuzzilli('FUZZILLI_CRASH', 8)", .shouldSucceed),

        // Crashes that indicate a sandbox violation should be detected.
        // This should crash with a wild write.
        ("fuzzilli('FUZZILLI_CRASH', 3)", .shouldCrash),
        // This should crash with an ASan-detectable use-after-free.
        ("fuzzilli('FUZZILLI_CRASH', 4)", .shouldCrash),
        // This should crash with an ASan-detectable out-of-bounds write.
        ("fuzzilli('FUZZILLI_CRASH', 6)", .shouldCrash),
        // This should crash due to calling abort_with_sandbox_violation().
        ("fuzzilli('FUZZILLI_CRASH', 9)", .shouldCrash),
        // This should crash due to executing an invalid machine code instruction.
        ("fuzzilli('FUZZILLI_CRASH', 11)", .shouldCrash),

        // Crashes that are not sandbox violations and so should be filtered out by the crash filter.
        // This triggers an IMMEDIATE_CRASH.
        ("fuzzilli('FUZZILLI_CRASH', 0)", .shouldNotCrash),
        // This triggers a CHECK failure.
        ("fuzzilli('FUZZILLI_CRASH', 1)", .shouldNotCrash),
        // This triggers a std::vector OOB access that should be caught by the libc++ hardening.
        ("fuzzilli('FUZZILLI_CRASH', 5)", .shouldNotCrash),
        // This triggers a `ud 2` which might for example be used for release asserts and so should be ignored.
        ("fuzzilli('FUZZILLI_CRASH', 10)", .shouldNotCrash),
    ],

    additionalCodeGenerators: [
        (ForceJITCompilationThroughLoopGenerator,  5),
        (ForceTurboFanCompilationGenerator,        5),
        (ForceMaglevCompilationGenerator,          5),
        (ForceOsrGenerator,                        5),
        (V8GcGenerator,                           10),
        (WasmStructGenerator,                      5),
        (WasmArrayGenerator,                       5),
        (SharedObjectGenerator,                    5),
        (PretenureAllocationSiteGenerator,         5),
        (HoleNanGenerator,                         5),
        (UndefinedNanGenerator,                    5),
        (StringShapeGenerator,                     5),
    ],

    additionalProgramTemplates: WeightedList<ProgramTemplate>([
        (BytecodeFuzzer, 2)
    ]),

    disabledCodeGenerators: [],

    disabledMutators: [],

    additionalBuiltins: [
        "gc"                                            : .function([.opt(gcOptions.instanceType)] => (.undefined | .jsPromise)),
        "d8"                                            : .object(),
        "Worker"                                        : .constructor([.jsAnything, .object()] => .object(withMethods: ["postMessage","getMessage"])),
    ],

    additionalObjectGroups: [jsD8, jsD8Test, jsD8FastCAPI, gcOptions],

    additionalEnumerations: [.gcTypeEnum, .gcExecutionEnum],

    optionalPostProcessor: SandboxFuzzingPostProcessor()
)

