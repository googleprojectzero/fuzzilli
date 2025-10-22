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

import Fuzzilli


// A post-processor that inserts calls to the `corrupt` function (defined in the prefix below) into the generated samples.
fileprivate struct SandboxFuzzingPostProcessor: FuzzingPostProcessor {
    func process(_ program: Fuzzilli.Program, for fuzzer: Fuzzer) -> Fuzzilli.Program {
        // We don't instrument every generated program since we still want the fuzzer to make progress towards
        // discovering more interestesting programs and adding them to the corpus. Corrupting objects in every
        // generated program might hamper that.
        if probability(0.5) { return program }

        let b = fuzzer.makeBuilder(forMutating: program)

        func corruptSomething() {
            // Make sure that we get a JS variable that is not a primitive.
            guard let target = b.findVariable(satisfying: { v in
                !b.type(of: v).Is(.primitive) && b.type(of: v).Is(.jsAnything)
            }) else { return }
            let numCorruptions = Int.random(in: 1...3)
            for _ in 0..<numCorruptions {
                let seed = UInt32.random(in: 0...UInt32.max)
                b.eval("corrupt(%@, \(seed))", with: [target])
            }
        }

        b.adopting(from: program) {
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

let v8SandboxProfile = Profile(
    processArgs: { randomize in
        var args = [
            "--expose-gc",
            "--omit-quit",
            "--allow-natives-syntax",
            "--fuzzing",
            "--jit-fuzzing",
            "--sandbox-fuzzing",
            // This is so that we get an ASan splat directly in the reproducer file.
            "--disable-in-process-stack-traces"
        ]

        return args
    },

    // ASan options.
    // - abort_on_error=true: We need asan to exit in a way that's detectable for Fuzzilli as a crash
    // - symbolize=false: Symbolization can tak a _very_ long time (> 1s), which may cause crashing samples to time out before the stack trace has been captured (in which case Fuzzilli will discard the sample)
    // - redzone=128: This value is used by Clusterfuzz for reproducing testcases so we should use the same value
    processEnv: ["ASAN_OPTIONS" : "abort_on_error=1:symbolize=false:redzone=128", "UBSAN_OPTIONS" : "abort_on_error=1:symbolize=false:redzone=128"],

    maxExecsBeforeRespawn: 1000,

    // ASan builds are slower, so we use a larger timeout.
    timeout: 600,

    codePrefix: """
                //
                // BEGIN FUZZER GENERATED CODE
                //

                """,

    codeSuffix: """

                //
                // BEGIN FUZZER HELPER CODE
                //

                // Corrupt the given object in a deterministic fashion (when using the same seed) and log the steps being performed.
                function corrupt(obj, seed) {
                    // In general, in this function memory contents is represented as (unsigned) BigInt, everything else (addresses, offsets, etc.) are Numbers.

                    function assert(c) {
                        if (!c) {
                            throw new Error("Assertion failed!");
                        }
                    }

                    const kHeapObjectTag = 0x1n;
                    // V8 uses the two lowest bits as tag bits: 0x1 to indicate HeapObject vs Smi and 0x2 to indicate a weak reference.
                    const kHeapObjectTagMask = 0x3n;
                    // Offsets should be a multiple of 4, as that's the typical field size.
                    const kOffsetAlignmentMask = ~0x3;

                    // Helper class for accessing in-sandbox memory.
                    class Memory {
                        constructor() {
                            let buffer = new Sandbox.MemoryView(0, 0x100000000);
                            this.dataView = new DataView(buffer);
                            this.taggedView = new Uint32Array(buffer);
                        }

                        read32(addr) {
                            return BigInt(this.dataView.getUint32(addr, true));
                        }

                        write32(addr, value) {
                            this.dataView.setUint32(addr, Number(value), true);
                        }

                        read16(addr) {
                            return BigInt(this.dataView.getUint16(addr, true));
                        }

                        write16(addr, value) {
                            this.dataView.setUint16(addr, Number(value), true);
                        }

                        read8(addr) {
                            return BigInt(this.dataView.getUint8(addr));
                        }

                        write8(addr, value) {
                            this.dataView.setUint8(addr, Number(value));
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
                    if (typeof this.memory_corruption_worker === 'undefined') {
                        // Define as non-configurable and non-enumerable property.
                        let worker = new Worker(workerFunc, {type: 'function'});
                        Object.defineProperty(this, 'memory_corruption_worker', {value: worker});
                    }

                    // Simple, seedable PRNG based on a LCG.
                    class RNG {
                        m = 2 ** 32;
                        a = 1664525;
                        c = 1013904223;
                        x;

                        constructor(seed) {
                            this.x = seed;
                        }

                        randomInt() {
                            this.x = (this.x * this.a + this.c) % this.m;
                            return this.x;
                        }

                        randomBigInt() {
                            return BigInt(this.randomInt());
                        }

                        randomIntBelow(n) {
                            return Math.floor(this.randomFloat() * n);
                        }

                        randomBigIntBelow(n) {
                            return BigInt(this.randomIntBelow(Number(n)));
                        }

                        randomBigIntInHalfOpenRange(lower, upper) {
                            assert(upper > lower);
                            let diff = upper - lower;
                            return lower + this.randomBigIntBelow(diff);
                        }

                        randomFloat() {
                            return this.randomInt() / this.m;
                        }

                        probability(p) {
                            return this.randomFloat() < p;
                        }

                        randomElement(array) {
                            assert(array.length > 0);
                            let randomIndex = this.randomIntBelow(array.length)
                            return array[randomIndex];
                        }
                    }

                    // Helper class implementing the various binary mutations.
                    class Mutator {
                        rng;

                        constructor(rng) {
                            this.rng = rng;
                        }

                        mutate(value, numBits) {
                            assert(numBits <= 32);
                            let allMutations = [this.#mutateBitflip, this.#mutateIncrement, this.#mutateReplace];
                            let mutate = this.rng.randomElement(allMutations);
                            return mutate.call(this, value, BigInt(numBits));
                        }

                        #mutateBitflip(value, numBits) {
                            let bitPosition = this.rng.randomBigIntBelow(numBits);
                            let bit = 1n << bitPosition;
                            return value ^ bit;
                        }

                        #mutateIncrement(value, numBits) {
                            let increment = this.#generateRandomBigInt(numBits);
                            if (increment == 0n) increment = 1n;
                            return (value + increment) & ((1n << numBits) - 1n);

                        }

                        #mutateReplace(value, numBits) {
                            return this.#generateRandomBigInt(numBits);
                        }

                        #generateRandomBigInt(numBits) {
                            // Generate a random integer, giving uniform weight to each order of magnitude (power-of-two).
                            // In other words, this function is equally likely to generate an integer in the range [n, 2n) or [2n, 4n).
                            let magnitude = this.rng.randomBigIntBelow(numBits + 1n);     // Between [0, numBits]
                            let upper = 1n << magnitude;
                            let lower = upper >> 1n;
                            return this.rng.randomBigIntInHalfOpenRange(lower, upper);
                        }
                    }

                    // Helper function to deterministically find a random neighbor object.
                    //
                    // This logic is designed to deal with a (somewhat) non-deterministic heap layout to ensure that test cases are reproducible.
                    // In practice, it should most of the time find the same neighbor object if (a) that object is always allocated after the
                    // start object, (b) is within the first N (currently 100) objects, and (c) is always the first neighbor of its instance type.
                    //
                    // This is achieved by iterating over the heap starting from the start object and computing a simple 16-bit hash value for each
                    // object. At the end, we select the first object whose hash is closest to a random 16-bit integer taken from the rng (which
                    // behaves deterministically). Note that we always take the first object if there are multiple object with the same instance
                    // type. For finding later neighbors, we rely on the |corrupt| logic to recursively pick neighbor objects.
                    function findRandomNeighborObject(addr, rng) {
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

                        let query = rng.randomInt() & 0xffff;
                        let currentWinner = addr;
                        let currentBest = kUint16Max;

                        for (let i = 0; i < N; i++) {
                            addr += Sandbox.getSizeOfObjectAt(addr);
                            let typeId = Sandbox.getInstanceTypeIdOfObjectAt(addr);
                            if (typeId == kUnknownInstanceId) {
                                // We found a corrupted object or went past the end of a page. No point in searching any further.
                                break;
                            }
                            let hash = hash16(typeId);
                            let score = Math.abs(hash - query);
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
                        let size = Sandbox.getSizeOfObjectAt(source);
                        // Simple way to get a placeholder object that's large enough: create a sequential string.
                        // TODO(saelo): maybe add a method to the sandbox api to construct an object of the appropriate size.
                        let placeholder = Array(size).fill("a").join("");
                        let destination = Sandbox.getAddressOf(placeholder);
                        memory.copyTagged(source, destination, size);
                        return destination;
                    }

                    // Helper function implementing the object corruption logic.
                    function corruptObjectAt(addr, rng, depth) {
                        let indent = "  ".repeat(depth + 1);
                        if (depth >= 10) {
                            print(indent + "Too much recursion, bailing out.");
                            return;
                        }

                        // We cannot corrupt read-only objects (or any objects referenced from them, as they must also be read-only).
                        // This is simply an optimization, otherwise we would crash during the memory write below.
                        if (!Sandbox.isWritableObjectAt(addr)) {
                            print(indent + "Not corrupting read-only object");
                            return;
                        }

                        let instanceType = Sandbox.getInstanceTypeOfObjectAt(addr);
                        print(indent + "Corrupting object at 0x" + addr.toString(16) + " of type " + instanceType);

                        // Some of the time, find a neighbor object to corrupt instead.
                        // This allows the fuzzer to discover and corrupt objects that are not directly referenced from a visible JavaScript variable.
                        if (rng.probability(0.25)) {
                            let newAddr = findRandomNeighborObject(addr, rng);
                            print(indent + "Recursively corrupting neighboring object at offset " + (newAddr - addr));
                            return corruptObjectAt(newAddr, rng, depth + 1);
                        }

                        // Determine a random field to corrupt.
                        let size = Sandbox.getSizeOfObjectAt(addr);
                        let offset = (rng.randomInt() % size) & kOffsetAlignmentMask;

                        // Check if the field currently contains a pointer to another object. In that case, (most of the time) corrupt that other object instead.
                        let oldValue = memory.read32(addr + offset);
                        let isLikelyPointer = (oldValue & kHeapObjectTag) == kHeapObjectTag;
                        if (isLikelyPointer && rng.probability(0.75)) {
                            let newAddr = Number(oldValue & ~kHeapObjectTagMask);
                            if (Sandbox.isValidObjectAt(newAddr)) {
                                print(indent + "Recursively corrupting object referenced through pointer at offset " + offset);
                                if (!Sandbox.isWritableObjectAt(newAddr)) {
                                    // We cannot corrupt the referenced object, so instead we create a copy of it and corrupt that instead.
                                    newAddr = copyObjectAt(newAddr);
                                    memory.write32(addr + offset, BigInt(newAddr) | kHeapObjectTag);
                                    print(indent + "Referenced object is in read-only memory. Creating and corrupting a copy instead");
                                }
                                return corruptObjectAt(newAddr, rng, depth + 1);
                            }
                        }

                        // Finally, corrupt the object!
                        let numBitsToCorrupt = rng.randomElement([8, 16, 32]);
                        let mutator = new Mutator(rng);
                        let newValue;
                        switch (numBitsToCorrupt) {
                            case 8:
                                offset += rng.randomIntBelow(4);
                                oldValue = memory.read8(addr + offset);
                                newValue = mutator.mutate(oldValue, 8);
                                memory.write8(addr + offset, newValue);
                                break;
                            case 16:
                                offset += rng.randomIntBelow(2) * 2;
                                oldValue = memory.read16(addr + offset);
                                newValue = mutator.mutate(oldValue, 16);
                                memory.write16(addr + offset, newValue);
                                break;
                            case 32:
                                oldValue = memory.read32(addr + offset);
                                newValue = mutator.mutate(oldValue, 32);
                                memory.write32(addr + offset, newValue);
                                break;
                        }

                        assert(oldValue >= 0 && oldValue < (1n << BigInt(numBitsToCorrupt)));
                        assert(newValue >= 0 && newValue < (1n << BigInt(numBitsToCorrupt)));

                        print(indent + "Corrupted " + numBitsToCorrupt + "-bit field at offset " + offset + ". Old value: 0x" + oldValue.toString(16) + ", new value: 0x" + newValue.toString(16));

                        // With low probability, keep flipping this value between the old and new value on a background worker thread.
                        if (rng.probability(0.10)) {
                            print(indent + "Will keep flipping this field between old and new value on background worker");
                            this.memory_corruption_worker.postMessage({address: addr + offset, valueA: Number(oldValue), valueB: Number(newValue), size: numBitsToCorrupt});
                        }
                    }

                    let addr;
                    try {
                        addr = Sandbox.getAddressOf(obj);
                    } catch (e) {
                        // Presumably, |obj| is a Smi, not a HeapObject.
                        return;
                    }

                    print("Corrupting memory starting from object at 0x" + addr.toString(16) + " with RNG seed " + seed);
                    corruptObjectAt(addr, new RNG(seed), 0);
                }
                """,

    ecmaVersion: ECMAScriptVersion.es6,

    startupTests: [
        // This makes sure that the fuzzilli builtin exists.
        ("fuzzilli('FUZZILLI_PRINT', 'test')", .shouldSucceed),
        // This makes sure that the memory corruption api is available.
        ("Sandbox.getAddressOf([1, 2, 3])", .shouldSucceed),
        // This makes sure that the |corrupt| function is available and working. It whould not corrupt anything as it's passed an object in read-only space ('undefined').
        ("corrupt(undefined, 42);", .shouldSucceed),
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

        // Crashes that are not sandbox violations and so should be filtered out by the crash filter.
        // This triggers an IMMEDIATE_CRASH.
        ("fuzzilli('FUZZILLI_CRASH', 0)", .shouldNotCrash),
        // This triggers a CHECK failure.
        ("fuzzilli('FUZZILLI_CRASH', 1)", .shouldNotCrash),
        // This triggers a std::vector OOB access that should be caught by the libc++ hardening.
        ("fuzzilli('FUZZILLI_CRASH', 5)", .shouldNotCrash),
    ],

    additionalCodeGenerators: [
        (ForceJITCompilationThroughLoopGenerator,  5),
        (ForceTurboFanCompilationGenerator,        5),
        (ForceMaglevCompilationGenerator,          5),
        (V8GcGenerator,                           10),
    ],

    additionalProgramTemplates: WeightedList<ProgramTemplate>([
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

