# Fuzzilli

A (coverage-)guided fuzzer for dynamic language interpreters based on a custom intermediate language ("FuzzIL") which can be mutated and translated to JavaScript.

Written and maintained by Samuel Groß, <saelo@google.com>.

## Usage

The basic steps to use this fuzzer are:

1. Download the source code for one of the supported JavaScript engines (currently [JavaScriptCore](https://github.com/WebKit/webkit), [Spidermonkey](https://github.com/mozilla/gecko-dev), and [v8](https://github.com/v8/v8)).
2. Apply the corresponding patch from the [Targets/](Targets/) directory. Also see the README.md in that directory.
3. Compile the engine with coverage instrumentation (requires clang >= 4.0) as described in the README.
4. Compile the fuzzer: `swift build [-c release]`. On Linux you will also need to supply `-Xlinker='-lrt'` as argument to `swift build`.
5. Run the fuzzer: `swift run [-c release] FuzzilliCli --profile=<profile> [other cli options] /path/to/jsshell`. On linux you will again need `-Xlinker='-lrt'`. See also `swift run FuzzilliCli --help`.

### Hacking

Check out [main.swift](Sources/FuzzilliCli/main.swift) to see a usage example of the Fuzzilli library and play with the various configuration options. Next, take a look at [Fuzzer.swift](Sources/Fuzzilli/Fuzzer.swift) for the highlevel fuzzing logic. From there dive into any part that seems interesting.

Patches, additions, other contributions etc. to this project are very welcome! However, do quickly check [the notes for contributors](CONTRIBUTING.md). Fuzzilli roughly follows [Google's code style guide for swift](https://google.github.io/swift/).

It would be much appreciated if you could send a short note (possibly including a CVE number) to <saelo@google.com> for any vulnerability found with the help of this project. Other than that you can of course claim any bug bounty, CVE credits, etc. for the vulnerabilities :)

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

### Processing Model

There is one fuzzer instance per target process. This enables synchronous execution of programs and thereby simplifies the implementation of various algorithms such as consecutive mutations and minimization. Moreover, it avoids the need to implement thread-safe access to internal state, e.g. the corpus. Each fuzzer instance has its own dedicated [DispatchQueue](https://developer.apple.com/documentation/dispatch), conceptually corresponding to a single thread. Every interaction with a fuzzer instance must then happen on the instance’s DispatchQueue. This guarantees thread-safety as the queue is serial.

To scale, fuzzer instances can become workers, in which case they report newly found interesting samples and crashes to a master instance. In turn, the master instances also synchronize their corpus with the workers. Communication between masters and workers can happen in different ways, each implemented as a module:

* [Inter-thread communication](Sources/Fuzzilli/Modules/ThreadSync.swift): synchronize instances in the same process by enqueuing tasks to the other fuzzer’s DispatchQueue.
* Inter-process communication (TODO): synchronize instances over an IPC channel.
* [Inter-machine communication](Sources/Fuzzilli/Modules/NetworkSync.swift): synchronize instances over a simple TCP-based protocol.

This design allows the fuzzer to scale to many cores on a single machine as well as to many different machines. As one master instance can quickly become overloaded if too many workers send programs to it, it is also possible to configure multiple tiers of master instances, e.g. one master instance, 16 intermediate masters connected to the master, and 256 workers connected to the intermediate masters.

## Resources

Further resources about this fuzzer:

* A [presentation](https://saelo.github.io/presentations/offensivecon_19_fuzzilli.pdf) about Fuzzilli given at Offensive Con 2019.
* The [master's thesis](https://saelo.github.io/papers/thesis.pdf) for which the initial implementation was done.

## Disclaimer

This is not an officially supported Google product.
