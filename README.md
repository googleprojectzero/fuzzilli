# Fuzzilli

A (coverage-)guided fuzzer for dynamic language interpreters based on a custom intermediate language ("FuzzIL") which can be mutated and translated to JavaScript.

Written and maintained by Samuel Groß, <saelo@google.com>.

## Usage

The basic steps to use this fuzzer are:

1. Download the source code for one of the supported JavaScript engines (currently [JavaScriptCore](https://github.com/WebKit/webkit), [Spidermonkey](https://github.com/mozilla/gecko-dev), and [v8](https://github.com/v8/v8)).
2. Apply the corresponding patch from the [Targets/](Targets/) directory. Also see the README.md in that directory.
3. Compile the engine with coverage instrumentation (requires clang >= 4.0) as described in the README.
4. Compile the fuzzer: `swift build [-c release]`.
5. Run the fuzzer: `swift run [-c release] FuzzilliCli --profile=<profile> [other cli options] /path/to/jsshell`. See also `swift run FuzzilliCli --help`.

### Hacking

Check out [main.swift](Sources/FuzzilliCli/main.swift) to see a usage example of the Fuzzilli library and play with the various configuration options. Next, take a look at [Fuzzer.swift](Sources/Fuzzilli/Fuzzer.swift) for the highlevel fuzzing logic. From there dive into any part that seems interesting.

Patches, additions, other contributions etc. to this project are very welcome! However, do quickly check [the notes for contributors](CONTRIBUTING.md). Fuzzilli roughly follows [Google's code style guide for swift](https://google.github.io/swift/).

It would be much appreciated if you could send a short note (possibly including a CVE number) to <saelo@google.com> or open a pull request for any vulnerability found with the help of this project so it can be included in the [bug showcase](#bug-showcase) section. Other than that you can of course claim any bug bounty, CVE credits, etc. for the vulnerabilities :)

## Concept

When fuzzing for core interpreter bugs, e.g. in JIT compilers, semantic correctness of generated programs becomes a concern. This is in contrast to most other scenarios, e.g. fuzzing of runtime APIs, in which case semantic correctness can easily be worked around by wrapping the generated code in try-catch constructs. There are different possibilities to achieve an acceptable rate of semantically correct samples, one of them being a mutational approach in which all samples in the corpus are also semantically valid. In that case, each mutation only has a small chance of turning a valid sample into an invalid one.

To implement a mutation-based JavaScript fuzzer, mutations to JavaScript code have to be defined. Instead of mutating the AST, or other syntactic elements of a program, a custom intermediate language (IL) is defined on which mutations to the control and data flow of a program can more directly be performed. This IL is afterwards translated to JavaScript for execution. The intermediate language looks roughly as follows:

    v0 <− LoadInt '0'
    v1 <− LoadInt '10'
    v2 <− LoadInt '1'
    v3 <− Phi v0
    BeginFor v0, '<', v1, '+', v2 −> v4
       v6 <− BinaryOperation v3, '+', v4
       Copy v3, v6
    EndFor
    v7 <− LoadString 'Result: '
    v8 <− BinaryOperation v7, '+', v3
    v9 <− LoadGlobal 'console'
    v10 <− CallMethod v9, 'log', [v8]

Which can e.g. be trivially translated to the following JavaScript code:

    const v0 = 0;
    const v1 = 10;
    const v2 = 1;
    let v3 = v0;
    for (let v4 = v0; v4 < v1; v4 = v4 + v2) {
        const v6 = v3 + v4;
        v3 = v6;
    }
    const v7 = "Result: ";
    const v8 = v7 + v3;
    const v9 = console;
    const v10 = v9.log(v8);

Or to the following JavaScript code by inlining intermediate expressions:

    let v3 = 0;
    for (let v4 = 0; v4 < 10; v4++) {
        v3 = v3 + v4;
    }
    console.log("Result: " + v3);

FuzzIL has a number of properties:

* A FuzzIL program is simply a list of instructions.
* A FuzzIL instruction is an operation together with input and output variables and potentially one or more parameters (enclosed in single quotes in the notation above).
* Inputs to instructions are always variables, there are no immediate values.
* The code is in SSA form: every variable is only assigned once. However, variables produced by a `Phi` operation can be reassigned later through a `Copy` operation.
* Every variable is defined before it is used.

A number of mutations can then be performed on these programs:

* [InputMutator](Sources/Fuzzilli/Mutators/InputMutator.swift): a simple data flow mutation in which an input value of an instruction is replaced by a different one.
* [CombineMutator](Sources/Fuzzilli/Mutators/CombineMutator.swift) and [SpliceMutator](Sources/Fuzzilli/Mutators/SpliceMutator.swift): these combine multiple programs by inserting (a part of) a program into another one.
* [InsertionMutator](Sources/Fuzzilli/Mutators/InsertionMutator.swift): generates new code from a list of [predefined code generators](Sources/Fuzzilli/Core/CodeGenerators.swift) at random positions in an existing program.
* [OperationMutator](Sources/Fuzzilli/Mutators/OperationMutator.swift): mutates the parameters of operations, e.g. replacing an integer constant by a different one.
* and many more...

## Implementation

The fuzzer is implemented in [Swift](https://swift.org/), with some parts (e.g. coverage measurements, socket interactions, etc.) implemented in C.

### Architecture

A fuzzer instance (implemented in [Fuzzer.swift](Sources/Fuzzilli/Fuzzer.swift)) is made up of the following central components:

* [FuzzerCore](Sources/Fuzzilli/Core/FuzzerCore.swift): produces new programs from existing ones by applying [mutations](Sources/Fuzzilli/Mutators). Afterwards executes the produced samples and evaluates them.
* [ScriptRunner](Sources/Fuzzilli/Execution): executes programs of the target language.
* [Corpus](Sources/Fuzzilli/Core/Corpus.swift): stores interesting samples and supplies them to the core fuzzer.
* [Environment](Sources/Fuzzilli/Core/JavaScriptEnvironment.swift): has knowledge of the runtime environment, e.g. the available builtins, property names, and methods.
* [Minimizer](Sources/Fuzzilli/Minimization/Minimizer.swift): minimizes crashing and interesting programs.
* [Evaluator](Sources/Fuzzilli/Evaluation): evaluates whether a sample is interesting according to some metric, e.g. code coverage.
* [Lifter](Sources/Fuzzilli/Lifting): translates a FuzzIL program to the target language (JavaScript).

Furthermore, a number of modules are optionally available:

* [Statistics](Sources/Fuzzilli/Modules/Statistics.swift): gathers various pieces of statistical information.
* [NetworkWorker/NetworkMaster](Sources/Fuzzilli/Modules/NetworkSync.swift): synchronize multiple instances over the network.
* [ThreadWorker/ThreadMaster](Sources/Fuzzilli/Modules/ThreadSync.swift): synchronize multiple instances within the same process.
* [Storage](Sources/Fuzzilli/Modules/Storage.swift): stores crashing programs to disk.

The fuzzer is event-driven, with most of the interactions between different classes happening through events. Events are dispatched e.g. as a result of a crash or an interesting program being found, a new program being executed, a log message being generated and so on. See [Events.swift](Sources/Fuzzilli/Core/Events.swift) for the full list of events. The event mechanism effectively decouples the various components of the fuzzer and makes it easy to implement additional modules.

A FuzzIL program can be built up using a [ProgramBuilder](Sources/Fuzzilli/Core/ProgramBuilder.swift) instance. A ProgramBuilder provides methods to create and append new instructions, append instructions from another program, retrieve existing variables, query the execution context at the current position (e.g. whether it is inside a loop), and more.

### Execution

The fuzzer supports different modes of execution for the target engines:

* [Forkserver](Sources/Fuzzilli/Execution/Forkserver.swift): similar to [afl](http://lcamtuf.coredump.cx/afl/), this will stop execution in the child process after (parts of) the process initialization are completed, then fork a new child process for every generated sample.
* [REPRL (read-eval-print-reset-loop)](Sources/Fuzzilli/Execution/REPRL.swift): in this mode the target engine is modified to accept a script over some IPC channel, execute it, then reset its internal state and wait for the next script. This mode tends to be faster.

### Scalability

There is one fuzzer instance per target process. This enables synchronous execution of programs and thereby simplifies the implementation of various algorithms such as consecutive mutations and minimization. Moreover, it avoids the need to implement thread-safe access to internal state, e.g. the corpus. Each fuzzer instance has its own dedicated [OperationQueue](https://developer.apple.com/documentation/foundation/operationqueue), conceptually corresponding to a single thread. Every interaction with a fuzzer instance must then happen on the instance’s queue. This guarantees thread-safety as the queue is serial. For more details see [the docs](Docs/ProcessingModel.md).

To scale, fuzzer instances can become workers, in which case they report newly found interesting samples and crashes to a master instance. In turn, the master instances also synchronize their corpus with the workers. Communication between masters and workers can happen in different ways, each implemented as a module:

* [Inter-thread communication](Sources/Fuzzilli/Modules/ThreadSync.swift): synchronize instances in the same process by enqueuing tasks to the other fuzzer’s DispatchQueue.
* Inter-process communication (TODO): synchronize instances over an IPC channel.
* [Inter-machine communication](Sources/Fuzzilli/Modules/NetworkSync.swift): synchronize instances over a simple TCP-based protocol.

This design allows the fuzzer to scale to many cores on a single machine as well as to many different machines. As one master instance can quickly become overloaded if too many workers send programs to it, it is also possible to configure multiple tiers of master instances, e.g. one master instance, 16 intermediate masters connected to the master, and 256 workers connected to the intermediate masters.

## Resources

Further resources about this fuzzer:

* A [presentation](https://saelo.github.io/presentations/offensivecon_19_fuzzilli.pdf) about Fuzzilli given at Offensive Con 2019.
* The [master's thesis](https://saelo.github.io/papers/thesis.pdf) for which the initial implementation was done.

## Bug Showcase

The following is a list of some of the bugs found with the help of Fuzzilli. Only bugs with security impact are included in the list. Special thanks to all users of Fuzzilli who have reported bugs found by it!

#### WebKit/JavaScriptCore

* [Issue 185328](https://bugs.webkit.org/show_bug.cgi?id=185328): DFG Compiler uses incorrect output register for NumberIsInteger operation
* [CVE-2018-4299](https://www.zerodayinitiative.com/advisories/ZDI-18-1081/): performProxyCall leaks internal object to script
* [CVE-2018-4359](https://bugs.webkit.org/show_bug.cgi?id=187451): compileMathIC produces incorrect machine code
* [CVE-2019-8518](https://bugs.chromium.org/p/project-zero/issues/detail?id=1775): OOB access in FTL JIT due to LICM moving array access before the bounds check
* [CVE-2019-8558](https://bugs.chromium.org/p/project-zero/issues/detail?id=1783): CodeBlock UaF due to dangling Watchpoints
* [CVE-2019-8611](https://bugs.chromium.org/p/project-zero/issues/detail?id=1788): AIR optimization incorrectly removes assignment to register
* [CVE-2019-8623](https://bugs.chromium.org/p/project-zero/issues/detail?id=1789): Loop-invariant code motion (LICM) in DFG JIT leaves stack variable uninitialized
* [CVE-2019-8622](https://bugs.chromium.org/p/project-zero/issues/detail?id=1802): DFG's doesGC() is incorrect about the HasIndexedProperty operation's behaviour on StringObjects
* [CVE-2019-8671](https://bugs.chromium.org/p/project-zero/issues/detail?id=1822): DFG: Loop-invariant code motion (LICM) leaves object property access unguarded
* [CVE-2019-8672](https://bugs.chromium.org/p/project-zero/issues/detail?id=1825): JSValue use-after-free in ValueProfiles
* [CVE-2019-8678](https://bugs.webkit.org/show_bug.cgi?id=198259): JSC fails to run haveABadTime() when some prototypes are modified, leading to type confusions
* [CVE-2019-8685](https://bugs.webkit.org/show_bug.cgi?id=197691): JSPropertyNameEnumerator uses wrong structure IDs
* [CVE-2019-8765](https://bugs.chromium.org/p/project-zero/issues/detail?id=1915): GetterSetter type confusion during DFG compilation
* [CVE-2019-8820](https://bugs.chromium.org/p/project-zero/issues/detail?id=1924): Type confusion during bailout when reconstructing arguments objects
* [CVE-2020-3901](https://bugs.webkit.org/show_bug.cgi?id=206805): GetterSetter type confusion in FTL JIT code (due to not always safe LICM)

#### Gecko/Spidermonkey

* [CVE-2018-12386](https://ssd-disclosure.com/archives/3765/ssd-advisory-firefox-javascript-type-confusion-rce): IonMonkey register allocation bug leads to type confusions
* [CVE-2019-9791](https://bugs.chromium.org/p/project-zero/issues/detail?id=1791): IonMonkey's type inference is incorrect for constructors entered via OSR
* [CVE-2019-9792](https://bugs.chromium.org/p/project-zero/issues/detail?id=1794): IonMonkey leaks JS\_OPTIMIZED\_OUT magic value to script
* [CVE-2019-9816](https://bugs.chromium.org/p/project-zero/issues/detail?id=1808): unexpected ObjectGroup in ObjectGroupDispatch operation
* [CVE-2019-9813](https://bugs.chromium.org/p/project-zero/issues/detail?id=1810): IonMonkey compiled code fails to update inferred property types, leading to type confusions
* [CVE-2019-11707](https://bugs.chromium.org/p/project-zero/issues/detail?id=1820): IonMonkey incorrectly predicts return type of Array.prototype.pop, leading to type confusions

#### Chromium/v8

* [Issue 939316](https://bugs.chromium.org/p/project-zero/issues/detail?id=1799): Turbofan may read a Map pointer out-of-bounds when optimizing Reflect.construct
* [Issue 944062](https://bugs.chromium.org/p/project-zero/issues/detail?id=1809): JSCallReducer::ReduceArrayIndexOfIncludes fails to insert Map checks
* [CVE-2019-5831](https://bugs.chromium.org/p/chromium/issues/detail?id=950328): Incorrect map processing in V8
* [Issue 944865](https://bugs.chromium.org/p/chromium/issues/detail?id=944865): Invalid value representation in V8
* [CVE-2019-5841](https://bugs.chromium.org/p/chromium/issues/detail?id=969588): Bug in inlining heuristic
* [CVE-2019-5847](https://bugs.chromium.org/p/chromium/issues/detail?id=972921): V8 sealed/frozen elements cause crash
* [CVE-2019-5853](https://bugs.chromium.org/p/chromium/issues/detail?id=976627): Memory corruption in regexp length check
* [Issue 992914](https://bugs.chromium.org/p/project-zero/issues/detail?id=1923): Map migration doesn't respect element kinds, leading to type confusion

## Disclaimer

This is not an officially supported Google product.
