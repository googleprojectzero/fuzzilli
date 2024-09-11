# How Fuzzilli Works

This document aims to explain how Fuzzilli generates JavaScript code and how it can be tuned to search for different kinds of bugs. Fuzzilli features two main fuzzing engines: the mutation engine and the hybrid engine, which is essentially a combination of a purely generative component coupled with existing mutations. Before explaining how these engines work, this document first explains FuzzIL, the custom intermediate language around which Fuzzilli is built.

All of the mechanisms described in this document can be observed in action by using the `--inspect` CLI flag. If enabled, all programs written to disk (essentially the programs in the corpus as well as crashes) will have an additional .history file describing the "history" of the programs, namely the exact mutation, splicing, code generation, etc. steps that were performed to generate it.

This document is meant to be a living document, describing how Fuzzilli currently works.

## Goals of Fuzzilli
Besides the central goal of generating "interesting" JavaScript code, Fuzzilli also has to deal with the following two problems.

### Syntactical Correctness
If a program is syntactically invalid, it will be rejected early on during processing in the engine by the parser. Since Fuzzilli doesn’t attempt to find bugs in the language parsers, such an execution would thus effectively be wasted. As such, Fuzzilli strives to achieve a 100% syntactical correctness rate. This is achieved by construction through the use of FuzzIL, discussed next, which can only express syntactically valid JavaScript code.

### Semantic Correctness
In Fuzzilli, a program that raises an uncaught exception is considered to be semantically incorrect, or simply invalid. While it would be possible to wrap every (or most) statements into try-catch blocks, this would fundamentally change the control flow of the generated program and thus how it is optimized by a JIT compiler. Many JIT bugs can not be triggered through such a program. As such, it is essential that Fuzzilli generates semantically valid samples with a fairly high degree (as a baseline, Fuzzilli should aim for a correctness rate of above 50%).

This challenge is up to each fuzzing engine, and will thus be discussed separately for each of them.

## FuzzIL
Implementation: [FuzzIL/](https://github.com/googleprojectzero/fuzzilli/tree/main/Sources/Fuzzilli/FuzzIL) subdirectory

Fuzzilli is based on a custom intermediate language, called FuzzIL. FuzzIL is designed with four central goals:

* Facilitating meaningful code mutations
* Being easy to reason about statically (see the section about the type system)
* Being easy to lift to JavaScript
* Ensuring certain correctness properties of the resulting JavaScript code, such as syntactic correctness and definition of variables before their use

Fuzzilli internally exclusively operates on FuzzIL programs and only lifts them to JavaScript for execution. The high-level fuzzing pipeline with FuzzIL thus looks like this:

![Fuzzing with FuzzIL](images/fuzzing_with_fuzzil.png)

Lifting is performed by the [JavaScriptLifter](https://github.com/googleprojectzero/fuzzilli/blob/main/Sources/Fuzzilli/Lifting/JavaScriptLifter.swift) while the execution of the JavaScript code happens through the [REPRL](https://github.com/googleprojectzero/fuzzilli/blob/main/Sources/Fuzzilli/Execution/REPRL.swift) (read-eval-print-reset-loop) mechanism, which is in essence an implementation of [persistent fuzzing](https://lcamtuf.blogspot.com/2015/06/new-in-afl-persistent-mode.html) for JS engines that also provides feedback about whether the execution succeeded or not (it failed if the execution was terminated by an uncaught exception).

FuzzIL programs can be serialized into [protobufs](https://github.com/googleprojectzero/fuzzilli/blob/main/Sources/Fuzzilli/Protobuf/program.proto), which is done to store them to disk or [send them over the network](https://github.com/googleprojectzero/fuzzilli/blob/main/Sources/Fuzzilli/Modules/NetworkSync.swift) in the case of distributed fuzzing. A FuzzIl program in protobuf format can be converted to JavaScript or to FuzzIL’s textual representation using the FuzzILTool:

`swift run FuzzILTool --liftToFuzzIL path/to/program.protobuf`

FuzzIL strives to be mostly self-explanatory. For example, an imaginary FuzzIL sample might look like this

```
v0 <- BeginPlainFunctionDefinition -> v1, v2, v3
    v4 <- BinaryOperation v1 '+' v2
    SetProperty v3, 'foo', v4
EndPlainFunctionDefinition
v5 <- LoadString "Hello World"
v6 <- CreateObject ['bar': v5]
v7 <- LoadFloat 13.37
v8 <- CallFunction v0, [v7, v7, v6]
```

When inlining intermediate expressions, the same program lifted to JavaScript code could look like this

```javascript
function f0(a1, a2, a3) {
    a3.foo = a1 + a2;
}
const v6 = {bar: "Hello World"};
f0(13.37, 13.37, v6);
```

Or could look like this when using a trivial lifting algorithm:

```javascript
function f0(a1, a2, a3) {
    const v4 = a1 + a2;
    a3.foo = v4;
}
const v5 = "Hello World";
const v6 = {bar: v5};
const v7 = 13.37;
const v8 = f0(v7, v7, v6);
```

Ultimately, the used lifting algorithm likely doesn’t matter too much since the JavaScript engine's bytecode and JIT compiler will produce mostly identical results regardless of the syntactical representation of the code.

FuzzIL has a notion of "guarded" operations, which are operations that guard against runtime exceptions via a try-catch. For example, if a `CallFunction` operation may reasonably throw an exception (e.g. because the argument types are incorrect), it could be marked as guarded: `CallFunction v3, [v5, v6] (guarded)`. In that case, it would lift to JavaScript code such as
```javascript
try { v3(v5, v6); } catch {};
```
As the try-catch blocks generated for guarded operations can negatively influence the program's behavior (as described above), they should be used sparingly. Furthermore, Fuzzilli tries to convert guarded operations into unguarded ones during Minimization and through the FixupMutator, both of which are discussed further later on in this document.

FuzzIL has a number of properties:
* A FuzzIL program is simply a list of instructions.
* Every FuzzIL program can be lifted to syntactically valid JavaScript code.
* A FuzzIL instruction is an operation together with input and output variables and potentially one or more parameters (enclosed in single quotes in the notation above).
* Every variable is defined before it is used, and variable numbers are ascending and contiguous.
* Control flow is expressed through "blocks" which have at least a Begin and and End operation, but can also have intermediate operations, for example `BeginIf`, `BeginElse`, `EndIf`.
* Block instructions can have inner outputs (those following a '->' in the notation above) which are only visible in the newly opened scope (for example function parameters).
* Inputs to instructions are always variables, there are no immediate values.
* Every output of an instruction is a new variable, and existing variables can only be reassigned through dedicated operations such as the `Reassign` instruction.

## Mutating FuzzIL Code
FuzzIL is designed to facilitate various meaningful code mutations. In this section, the central mutations are explained.

It should be noted that [programs](https://github.com/googleprojectzero/fuzzilli/blob/main/Sources/Fuzzilli/FuzzIL/Program.swift) in Fuzzilli are immutable, which makes it easier to reason about them. As such, when a program is mutated, it is actually copied while mutations are applied to it. This is done through the [ProgramBuilder class](https://github.com/googleprojectzero/fuzzilli/blob/main/Sources/Fuzzilli/Base/ProgramBuilder.swift), a central component in Fuzzilli which allows generating new instructions or copying instructions from another program, and exposes various kinds of information about the program under construction, such as which variables are currently visible.

### Input Mutator
Implementation: [InputMutator.swift](https://github.com/googleprojectzero/fuzzilli/blob/main/Sources/Fuzzilli/Mutators/InputMutator.swift)

This is the central data flow mutation. In essence, it simply replaces an input to an instruction with another, randomly chosen one:

```
SetProperty v3, 'foo', v4
```

Might become

```
SetProperty v3, 'foo', v2
```

Due to the design of FuzzIL, in particular the fact that all inputs to instructions are variables, this mutation requires only a handful of LOCs to implement.

### Operation Mutator
Implementation: [OperationMutator.swift](https://github.com/googleprojectzero/fuzzilli/blob/main/Sources/Fuzzilli/Mutators/OperationMutator.swift)

Another fundamental mutation which mutates the parameters of an operation (the values enclosed in single quotes in FuzzIL's textual representation). For example:

```
v4 <- BinaryOperation v1 '+' v2
```

Might become

```
v4 <- BinaryOperation v1 '/' v2
```

### Splicing
Implementation: [SpliceMutator](https://github.com/googleprojectzero/fuzzilli/blob/main/Sources/Fuzzilli/Mutators/SpliceMutator.swift)

The idea behind splicing is to copy a self-contained part of one program into another in order to combine features from different programs. Consider the following program:

```
v0 <- LoadInt '42'
v1 <- LoadFloat '13.37'
v2 <- LoadBuiltin 'Math'
v3 <- CallMethod v2, 'sin', [v1]
v4 <- CreateArray [v3, v3]
```

In its simplest form, splicing from the `CallMethod` instruction would result in the three middle instructions being copied into the current program. This also requires renaming variables so they don’t collide with existing variables:

```
... existing code
v13 <- LoadFloat '13.37'
v14 <- LoadBuiltin 'Math'
v15 <- CallMethod v14, 'sin', [v13]
... existing code
```

More complex splices are also possible. For example, Fuzzilli will probabilistically remap some variables in the program being spliced from to "compatible" variables in the host program to combine the data-flows of the two programs, and so could also end up producing the following result:

```
... existing code
v14 <- LoadBuiltin 'Math'
v15 <- CallMethod v14, 'sin', [v3]
... existing code
```

Here, the splicing algorithm has decided to replace the `LoadFloat` operation with an existing variable (`v3`), for example because that variable also contains a float.

A trivial variant of the splice mutation is the [CombineMutator](https://github.com/googleprojectzero/fuzzilli/blob/main/Sources/Fuzzilli/Mutators/CombineMutator.swift) which simply inserts another program in full into the currently mutated one. In that case, the splice is essentially the entire program.

### Code Generation
Implementation: [CodeGenMutator.swift](https://github.com/googleprojectzero/fuzzilli/blob/main/Sources/Fuzzilli/Mutators/CodeGenMutator.swift)

The final fundamental mutation is code generation. This mutator generates new, random code at one or multiple random positions in the mutated program.

Code generation is performed through "CodeGenerators": small functions that generate a specific code fragment, often just a single FuzzIL instruction, while (usually) using existing variables as inputs if required. A very simple code generator would be the following:

```swift
CodeGenerator("IntegerGenerator") { b in
    b.loadInt(b.genInt())
}
```

This generator emits a LoadInteger instruction that creates a new variable containing a random integer value (technically, not completely random since `genInt()` will favor some "interesting" integers). Another example code generator might be:

```swift
CodeGenerator("ComparisonGenerator", inputs: (.anything, .anything)) { b, lhs, rhs in
    b.compare(lhs, with: rhs, using: chooseUniform(from: allComparators))
},
```

This generator emits a comparison instruction (e.g. `==`) comparing two existing variables (of arbitrary type).

The default code generators can be found in [CodeGenerators.swift](https://github.com/googleprojectzero/fuzzilli/blob/main/Sources/Fuzzilli/CodeGen/CodeGenerators.swift) while custom code generators can be added for specific engines, for example to [trigger different levels of JITing](https://github.com/googleprojectzero/fuzzilli/blob/main/Sources/FuzzilliCli/Profiles/JSCProfile.swift).

Code generators are stored in a weighted list and are thus selected with different, currently [manually chosen weights](https://github.com/googleprojectzero/fuzzilli/blob/main/Sources/Fuzzilli/CodeGen/CodeGeneratorWeights.swift). This allows some degree of control over the distribution of the generated code, for example roughly how often arithmetic operations or method calls are performed, or how much control flow (if-else, loops, ...) is generated relative to data flow. Furthermore, CodeGenerators provide a simple way to steer Fuzzilli towards certain bug types by adding CodeGenerators that generate code fragments that have frequently resulted in bugs in the past, such as prototype changes, custom type conversion callbacks (e.g. valueOf), or indexed accessors.

Through the code generators, all relevant language features (e.g. object operations, unary and binary operations, etc.) will eventually be generated, then kept in the corpus (because they trigger new coverage) and further mutated afterwards.

### Exploration
Implementation: [ExplorationMutator.swift](https://github.com/googleprojectzero/fuzzilli/blob/main/Sources/Fuzzilli/Mutators/ExplorationMutator.swift)

This advanced mutator uses runtime type information available in JavaScript to perform more intelligent mutations, in particular to determine possible actions that can be performed on an existing value. It does the following:
1. It inserts `Explore` operations for random existing variables in the program to be mutated
2. It executes the resulting (temporary) program. The `Explore` operations will be lifted
   to a sequence of code that inspects the variable at runtime (using features like 'typeof' and
   'Object.getOwnPropertyNames' in JavaScript) and selects a "useful" operation to perform
   on it (e.g. load a property, call a method, ...), then reports back what it did
3. The mutator processes the output of step 2 and replaces some of the Explore mutations
   with the concrete action that was selected at runtime. All other Explore operations are discarded.

The result is a program that performs useful actions on some of the existing variables even without
statically knowing their type. The resulting program is also deterministic and "JIT friendly" as it
no longer relies on any kind of runtime object inspection.

### Probing
Implementation: [ProbingMutator.swift](https://github.com/googleprojectzero/fuzzilli/blob/main/Sources/Fuzzilli/Mutators/ProbingMutator.swift)

This is another runtime-assisted mutator which tries to determine how an existing value is used. In particular, it tries to determine if certain properties should exist on an object. This mutator does the following:
1. It inserts `Probe` operations for random existing variables in the program
   to be mutated
2. It executes the resulting (temporary) program. The `Probe` operations will
   be lifted to a sequence of code that replaces the object (really, the
   object's prototype) with a Proxy, which then records all accesses to
   non-existant properties. The list of these is then sent back to Fuzzilli.
3. The mutator processes the output of step 2 and installs some of the missing
   properties and callbacks.

This mutator thereby achieves a few things:
1. It can automatically detect whether an operation triggers a callback, and
   can then install the callback function. This can for example help find bugs
   related to [unexpected callbacks](http://www.phrack.org/issues/70/3.html).
2. It can determine how a builtin API works and what kinds of arguments it
   expects. For example, many APIs require "config" objects that are expected
   to have certain keys. This mutator can determine what those keys are, making
   it possible to call those APIs in a useful way.
3. It can make existing code more useful. For example, we may already have a
   jit-optimized function that operates on an object argument, but accesses
   non-existant properties, which is likely not very useful. This mutator can
   ensure that those properties exist, making the overall program more
   meaningful.

### FixupMutator
Implementation: [FixupMutator.swift](https://github.com/googleprojectzero/fuzzilli/blob/main/Sources/Fuzzilli/Mutators/FixupMutator.swift)

This is the final runtime-assisted mutator. It's goal is to fix/improve existing code. In particular, it wants to
* Remove unecessary try-catch blocks and guards
* Fix accesses to non-existant properties and elements (TODO)
* Fix invalid function-, method-, or constructor calls (TODO)
* Fix arithmetic operations that result in NaN, which typically indicates that no meaningful operation was performed (TODO)

All but the first are not yet implemented, so this mutator is still work-in-progress.

The FixupMutator is one of two ways in which guarded operations are converted to unguarded ones (which are generally preferable).

## The Type System and Type Inference
Implementation: [TypeSystem.swift](https://github.com/googleprojectzero/fuzzilli/blob/main/Sources/Fuzzilli/FuzzIL/TypeSystem.swift) and [JSTyper.swift](https://github.com/googleprojectzero/fuzzilli/blob/main/Sources/Fuzzilli/FuzzIL/JSTyper.swift)

Up to this point, a code generator is a simple function that fetches zero or more random input variables and generates some new FuzzIL instructions to perform some operations on them. Now consider the following, imaginary code generator:

```swift
CodeGenerator("FunctionCallGenerator") { b in
    let function = b.randomVariable()
    let arguments = [b.randomVariable(), b.randomVariable(), b.randomVariable()]
    b.callFunction(f, with: arguments)
}
```

This generator selects a random, currently visible variable, then calls it as a function with three random arguments.

The problem here is that since only a small number of variables at any given time are actually functions, this generator will end up generating a lot of invalid function calls, such as the following:

```
v3 <- LoadString "foobar"
v4 <- CallFunction v3, []
// TypeError: v3 is not a function
```

This will cause a runtime exception to be thrown which then results in the rest of the program to not be executed and the program being considered invalid.

To deal with this problem, Fuzzilli implements a relatively simple type inference which attempts to infer the possible types of every variable while a program is constructed by the ProgramBuilder. This is (likely) easier than it sounds since the interpreter only needs to be correct most of the time (it’s basically an optimization), not always. This significantly simplifies the implementation as many operations with complex effects, such as prototype changes, can largely be ignored. As an example, consider the rules that infer the results of the typeof, instanceof, and comparison operations:

```swift
case is TypeOf:
    set(instr.output, environment.stringType)

case is InstanceOf:
    set(instr.output, environment.booleanType)

case is Compare:
    set(instr.output, environment.booleanType)
```

To correctly infer the types of builtin objects, methods, and functions, the type inference relies on a [static model of the JavaScript runtime environment](https://github.com/googleprojectzero/fuzzilli/blob/main/Sources/Fuzzilli/Environment/JavaScriptEnvironment.swift) which can, for example, tell the interpreter that the eval builtin is a function that expects a single argument, that the Object builtin is an object with various methods, or that the Uint8Array builtin is a constructor that returns a Uint8Array instance, which then has a certain set of properties and methods.

FuzzIL is designed to make type inference as simple as possible. As an example, consider the implementation of ES6 classes. In FuzzIL, they look roughly like this:

```
v0 <- BeginClassDefinition
ClassAddInstanceProperty "foo", v5
BeginClassInstanceMethod "bar" -> v8 (this), v9
    ... implementation of method "bar"
EndClassInstanceMethod
BeginClassInstanceMethod "baz" -> v6 (this)
    ... implementation of method "baz"
EndClassInstanceMethod
EndClassDefinition
```

With this it is fairly straight-forward to infer the type of the class' instances from the FuzzIL code: `.object(withProperties: ["foo"], withMethods: ["bar", "baz"])`.

With type information available, the CodeGenerator from above can now request a variable containing a function and can also attempt to find variables compatible with the function’s parameter types:

```swift
CodeGenerator("FunctionCallGenerator") { b in
    let function = b.randomVariable(ofType: .function())
    let arguments = b.randomArguments(forCalling: function)
    b.callFunction(f, with: arguments)
}
```

However, even with this change, the function call can still raise an exception if the argument values have the wrong type. Fuzzilli tries to deal with that in two ways:
1. If the type of the function is known (i.e. its signature is known),
   `randomArguments(forCalling:)` will try to find appropriate arguments.
2. If no matching arguments are found (or if the signature isn't known), the
   generator can optionally mark the call operation as "guarded". This will
   cause it to be wrapped in try-catch during lifing.

It is important to note that, for mutation-based fuzzing, the JSTyper and the type system should be seen as optimizations, not essential features, and so the fuzzer should still be able to function without type information. In addition, while the use of type information for mutations can improve the performance of the fuzzer (less trivially incorrect samples are produced), too much reliance on it might restrict the fuzzer and thus affect the performance negatively (less diverse samples are produced). An example of this is the InputMutator, which can optionally be type aware, in which case it will attempt to find "compatible" replacement variables. In order to not restrict the fuzzer too much, Fuzzilli's MutationEngine is currently configured to use a non-type-aware InputMutator as well as a type-aware InputMutator.

### Type System
Implementation: [TypeSystem.swift](https://github.com/googleprojectzero/fuzzilli/blob/main/Sources/Fuzzilli/FuzzIL/TypeSystem.swift)

To do its job, the JSTyper requires a type system. FuzzIL’s type system is designed to support two central use cases:

1. Determining the operations that can be performed on a given variable. For example, the type system is expected to state which properties and methods are available on an object and what their types and signatures are.
2. Finding a compatible variable for a given operation. For example, a function might require a certain argument type, e.g. a Number or a Uint8Array. The type system must be able to express these types and be able to identify variables that store a value of this type or of a subtype. For example, a Uint8Array with an additional property can be used when a Uint8Array is required, and an object of a subclass can be used when the parent class is required.

Both of these operations need to be efficient as they will be performed frequently.

The type system is constructed around bitsets, with the base types represented each by a single bit in a 32bit integer:

```swift
static let nothing     = BaseType([])
static let undefined   = BaseType(rawValue: 1 << 0)
static let integer     = BaseType(rawValue: 1 << 1)
static let bigint      = BaseType(rawValue: 1 << 2)
static let float       = BaseType(rawValue: 1 << 3)
static let boolean     = BaseType(rawValue: 1 << 4)
static let string      = BaseType(rawValue: 1 << 5)
static let regexp      = BaseType(rawValue: 1 << 6)
static let object      = BaseType(rawValue: 1 << 7)
static let function    = BaseType(rawValue: 1 << 8)
static let constructor = BaseType(rawValue: 1 << 9)
static let iterable    = BaseType(rawValue: 1 << 10)
static let anything    = BaseType([.undefined, .integer, .float, .string, .boolean, .object, .function, .constructor, .bigint, .regexp, .iterable])
```

Each base type expresses that certain actions can be performed of a value of its type (use case 1.). For example, the numerical types express that arithmetic operations can be performed on its values, the `.iterable` type expresses that the value can be iterated over (e.g. through a for-of loop or using the spread operator), the `.object` type expresses that the value has properties and methods that can be accessed, and the `.function` type expresses that the value can be invoked using a function call.

Additional type information, for example the properties and methods, the signatures of functions, or the element type of arrays, is stored in "type extension" objects which can be shared between multiple Type structs (to reduce memory consumption).

The base types can be combined to form more complex types using three operators: union, intersection, and merge. These are discussed next.

#### Union Operator
Operator: `|` (bitwise or)

A union expresses that a variable has one type or the other: the type `t1 | t2` expresses that a value is either a `t1` or a `t2`.

In Fuzzilli, union types can frequently occur as in- or output types of functions. For example, the [`String.prototype.replace`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String/replace) method can take both a regular expression object or a string as first parameter: `"replace" : [.string | .jsRegExp, .string] => .jsString`. In addition, union types also occur due to conditional execution:

```javascript
let v4 = 42; 		// .integer
if (v2) {
    v4 = "foobar"; 	// .string
}
// v4 = .integer | .string
```

#### Intersection Operator
Operator: `&` (bitwise and)

The intersection operator computes the intersection between two (union) types. For example, the intersection of `t1 | t2` with `t1 | t3` is `t1`.

In Fuzzilli, this operator is used to determine whether a variable may have a certain type, for example whether it could be a BigInt, in which case the resulting type of many arithmetic operators should also include BigInt.

#### Merge Operator
Operator: `+` (plus)

This operator is probably the least intuitive and is likely somewhat unique to this type system.

In essence, if a variable has the merged type `t1 + t2` then it is both input types at the same time. As such, it can be used whenever one of the original types is required. To see why this can be useful, consider a few common JavaScript values:

**A string: `"foobar"`**
While the JavaScript string is clearly of type "string", meaning it can for example be used to do string concatenation, it is also an object with properties (e.g. `.length`) and methods (e.g. `.charCodeAt`). Furthermore, it also behaves as an array as it can be iterated and spread. As such, a JavaScript string would be of type `.string + .object(...) + .array`

**A function: `function foo(...) { ... }`**
A JavaScript function is both a function (it can be called) as well as an object (it has properties and methods). As such, the type would be `.function(...) + .object(...)`

**An array: `[ ... ]`**
A JavaScript array is iterable, but also contains properties and methods and is thus represented by `.array + .object(...)`.

In essence, merge types allow FuzzIL to model the dynamic nature of the JavaScript language, in particular the implicit type conversions that are frequently performed and the fact that many things are (also) objects.

#### Type Subsumption
Operation: `<=` and `>=`

To support type queries (use case 2.), the type system implements a subsumption relationship between types. This can be thought of as the "is a" relationship and should generally be used when searching for "compatible" variables for a given type constraint.

The general subsumption rules are:
* Base types only subsume themselves (an integer is an integer but not a string)
* A union `t1 | t2` subsumes both `t1` and `t2` (a string is a "string or number")
* A merged type `t1 + t2` is subsumed by both `t1` and `t2` (a JavaScript function is both a function and an object with properties and methods)
* Inheritance relationships (including added properties/methods) work as expected: a Uint8Array with an additional property is still a Uint8Array. An instance of a subclass is also an instance of the parent class.

#### Implementation Details
Types are implemented as two 32bit integers, one storing the definite type and one storing the possible type. As a rule of thumb, the definite type grows through merging and the possible type grows through unioning.

Due to this representation, a type can generally either be a union type or a merged type. For example, it is not possible (if attempted, it will result in a runtime error) to merge union types, as this couldn’t be properly represented. In practice, however, this is not required and thus unproblematic. Unioning merged types is supported, however, the result is usually too broad. For example, the type `(t1 + t2) | (t3 + t4)` would be indistinguishable from the type `t1 | t2 | t3 | t4`. The result type is thus broader than necessary but still correct in the sense that the resulting type subsumes both input types. In practice, again, this does not really matter since this case only occurs during conditional execution, in which case the resulting type can probably not be used in a meaningful way anyway (it isn’t guaranteed to be any of the types, so it can’t be used when one of them is required).

#### Type Examples
To give a better understanding of FuzzIL’s type system, this section shows a few common JavaScript values and what their type in FuzzIL would be. This can also be inspected by using the `--inspect=types` flag. If enabled, programs written to disk will include the types of variables as comments.

```javascript
let v0 = "foobar";
// .string + .object(...) + .array
// the object part contains all the standard string methods and properties

let v0 = { valueOf() { ...; return 13.37; }};
// .object(...) + .float
// The object can be used for numerical operations since it has a meaningful
// conversion operator defined (a custom valueOf method with known signature).
// Note: this is not yet implemented, currently the type would just be .object

let v0 = [...];
// .array + .object(...)
// the JavaScript array is clearly an array (can be iterated over) but also
// exposes properties and methods and as such is also an object

class v0 { ... foo() { ... }; bar() { ... } };
// .constructor([...] => .object(...))
// The variable v0 is a constructor with the parameters indicated by its
// constructor and which returns an object of the v0 "group" with certain
// properties and methods (e.g. foo and bar)
```

## The Mutation Engine
Implementation: [MutationEngine.swift](https://github.com/googleprojectzero/fuzzilli/blob/main/Sources/Fuzzilli/Engines/MutationEngine.swift) (--engine=mutation)

This section will explain how Fuzzilli’s mutation engine works. For that, it first covers three of the missing components of the mutation engine, namely the minimizer, the corpus, and coverage collection, then explains the high-level fuzzing algorithm used by the mutation engine.

### Minimization
Implementation: [Minimization/](https://github.com/googleprojectzero/fuzzilli/tree/main/Sources/Fuzzilli/Minimization) subdirectory

The mutations that Fuzzilli performs all have one thing in common: they can only increase the size (the number of instructions) of a FuzzIL program, but never decrease it. As such, after many rounds of mutations, programs would eventually become too large to execute within the time limit. Moreover, if unnecessary features are not removed from interesting programs, the efficiency of future mutations degrades, as many mutations will be "wasted" mutating irrelevant code. As such, Fuzzilli requires a minimizer that removes unnecessary code from programs before they are inserted into the corpus.

Minimization is conceptually simple: Fuzzilli attempts to identify and remove instructions that are not necessary to trigger the newly discovered coverage edges. In the simplest case, this means [removing a single instruction, then rerunning the program to see if it still triggers the new edges](https://github.com/googleprojectzero/fuzzilli/blob/main/Sources/Fuzzilli/Minimization/GenericInstructionReducer.swift). There are also a few specialized minimization passes. For example, there is an [inlining reducer](https://github.com/googleprojectzero/fuzzilli/blob/main/Sources/Fuzzilli/Minimization/InliningReducer.swift) which attempts to inline functions at their callsite. This is necessary since otherwise code patterns such as

```javascript
function v1(...) {
    function v2(...) {
        function v3(...) {
        }
        v3(...);
    }
    v2(...);
}
v1(...);
```

would build up over time, for example when splicing function calls and definitions from another program into the current one.

As can be imagined, minimization is very expensive, frequently requiring over a hundred executions. However, while the minimization overhead dominates in the early stages of fuzzing (when interesting samples are frequently found), it approaches zero in the later stages of fuzzing when new, interesting programs are rarely found.

It is possible to tune the minimizer to remove code less aggressively through the `--minimizationLimit=N` CLI flag. With that, it is possible to force the minimizer to keep minimized programs above a given number of instructions. This can help retain some additional code fragments which might facilitate future mutations. This can also speed up minimization a bit since less instructions need to be removed. However, setting this value too high will likely result in the same kinds of problems that the minimizer attempts to solve in the first place.

Besides removing instructions, the Minimizer also tries to simplify programs in other ways. For example, it attempts to convert guarded operations into unguarded ones, remove unecessary arguments to function calls, merge variables containing the same values, and turns some complex instructions into simpler ones (e.g. spread calls into regular calls).

### Corpus
Implementation: [Corpus.swift](https://github.com/googleprojectzero/fuzzilli/blob/main/Sources/Fuzzilli/Corpus/Corpus.swift)

Fuzzilli keeps "interesting" samples in its corpus for future mutations. In the default corpus implementation, samples are added , then mutated randomly, and eventually "retired" after they have been mutated at least a certain number of times (controllable through `--minMutationsPerSample` flag). Other corpus management algorithms can be implemented as well. For example, an implementation of a [corpus management algorithm based on Markov Chains](https://mboehme.github.io/paper/TSE18.pdf) is [implemented](https://github.com/googleprojectzero/fuzzilli/pull/171).

If the `--storagePath` CLI flag is used, Fuzzilli will write all samples that it adds to its corpus to disk in their protobuf format. These can for example be used to resume a previous fuzzing session through `--resume` or they can be inspected with the FuzzILTool.

### Compiler
Implementation: [Compiler/](https://github.com/googleprojectzero/fuzzilli/tree/main/Sources/Fuzzilli/Compiler)

By default, Fuzzilli always starts from a single, arbitrarily chosen program in the corpus. It can be desirable to start from an existing corpus of programs, for example to find variants of past bugs. In Fuzzilli, this requires a compiler from JavaScript to FuzzIL as Fuzzilli can only operate on FuzzIL programs. Fuzzilli comes with such a compiler, which uses [babel.js](https://babeljs.io/) to parse JavaScript code, then a relatively straight-forward compiler that processes the resulting AST and produces a FuzzIL program from it. The compiler is not yet feature complete and support for more language constructs is needed.

### Coverage
Implementation: [Evaluation/](https://github.com/googleprojectzero/fuzzilli/tree/main/Sources/Fuzzilli/Evaluation) subdirectory

To determine whether a generated program should be added to the corpus, Fuzzilli relies on code coverage as a guidance metric. To obtain coverage information, the target JavaScript engines are compiled with `-fsanitize-coverage=trace-pc-guard` and a small code stub is added to them which collects edge coverage information during every execution of a JavaScript program through the REPRL interface. After every execution of a newly generated program, the coverage bitmap is processed to determine whether any new branches in the control flow graph of the JavaScript engine have been discovered (and so the coverage increased). If so, the sample is determined to be interesting and is added to the corpus after minimization.

It should be noted that, in the case of JIT compilers, Fuzzilli only collects coverage information on the compiler code and not on the generated code. This is much simpler than attempting to instrument the generated code (which will quickly change if the original JavaScript code is mutated). Moreover, it should generally be the case that the JIT compiler only compiles code that has been executed many times already. As such, the likelihood of the generated JIT code also being executed afterwards should be fairly high. In any case, investigating whether coverage guidance on the emitted JIT code can be used as a guidance metric remains the topic of future research.

### A Note on Determinism
Modern JavaScript engines perform various tasks on background threads, such as JIT compilation or garbage collection. This, amongst other reasons, can lead to non-deterministic behaviour: a sample might trigger a JIT compiler or GC edge once, but not during subsequent executions. If Fuzzilli kept such a sample, it would negatively affect the effectiveness of the mutation engine, for example because Fuzzilli would not be able to minimize the sample, and would subsequently "waste" many executions trying to mutate it. To deal with that, Fuzzilli by default ensures that newly found samples trigger the new edges deterministically. This is achieved by repeatedly executing the sample and forming the intersection of the triggered edges until that intersection becomes stable. Additionally, when using distributed fuzzing, worker instances will re-execute samples when importing them, thus also ensuring deterministic behaviour.

As crashes related to non-deterministic behaviour might be hard to reproduce but could still be interesting, Fuzzilli includes the original failure message (for example, the assertion failure message and stacktrace) as well as the exit code as a comment in the reproducer sample to help with the anslysis.

### The Mutation Algorithm
Fuzzilli’s mutation engine follows the typical procedure of a mutation-based fuzzer: a sample (in Fuzzilli’s case a FuzzIL program) is taken from the corpus and mutated a given number of times. During mutations, the types of variables are approximated through the JSTyper to allow smarter mutations. If, at any point, the mutated sample triggers new coverage, it is added to the corpus after being minimized. However, to achieve a high degree of semantic correctness, the mutation engine will revert a mutation if it resulted in an invalid program. This ensures a high degree of semantic correctness, as only valid programs are mutated and because every mutation only has a relatively low probability of turning a valid program into an invalid one.

The high-level algorithm implemented by the mutation engine is summarized in the image below.

![Mutation Engine Algorithm](images/mutation_engine.png)

## Limitations of the Mutation Engine
Disclaimer: this section is mostly based on thought experiments, existing fuzzing research, intuition, [found](https://github.com/googleprojectzero/fuzzilli#bug-showcase) (and especially non-found) vulnerabilities, and occasional corpus inspection instead of dedicated experiments or measurements.

This section attempts to discuss the limitations of the mutation engine from a theoretical standpoint.

A fuzzer can be viewed as a tool that samples from a universe of possible inputs. From that viewpoint, Fuzzilli would sample from the universe of all syntactically valid JavaScript programs. A general principle of Fuzzilli is that it should not attempt to sample (uniformly) from the entire universe of syntactically valid JavaScript programs since that universe is simply too large. Due to that, some form of guidance is required to (hopefully) direct the fuzzer towards samples that are more likely to trigger bugs. In the MutationEngine, this guidance (mostly) comes from coverage feedback which automatically steers the fuzzer towards code areas with high complexity. Additional, manual guidance can be used to bias the fuzzer, such as through specific CodeGenerators designed to trigger JIT compilation. With that, the mutation engine then essentially samples from the set of programs that are reachable by applying N consecutive mutations to a program in the corpus, while the programs in the corpus are those that trigger new coverage. It should further be the case that the "farther away" a sample is from the corpus, the less likely it is to be found, as the number of possible mutation "paths" of length N that lead to it decreases (i.e. a sample that is very close to a sample in the corpus can likely be found through many different mutations, while a sample that is far away requires a specific sequence of mutations to reach).

The MutationEngine would then be able to find bugs that are somewhat "close" to those in the corpus, but not ones that are far away from that.

The key question is then how the distribution of the samples in the corpus is likely to look, as that greatly influences the overall distribution of the generated samples. Here, the thesis is that samples in the corpus will usually only trigger one or a few features of the engine since it is unlikely that a new program triggers multiple new, complex optimizations at once. This can be measured to some degree by looking at the number of newly discovered edges (`--inspect` will include it) of the samples in a typical corpus. The table below shows this for a fuzzing run against JavaScriptCore with roughly 20000 samples:

Number of new Edges | Number of Samples | % of Total | Avg. size (in JS LoC)
--------------------|-------------------|------------|----------------------
1                   | 9631              | 48%        | 40
2-5                 | 5999              | 30%        | 61
6-10                | 1580              | 8%         | 69
10+                 | 2849              | 14%        | 74

As such, likely one of the biggest shortcomings of the MutationEngine is that it will struggle to find vulnerabilities that require multiple different operations to be performed on related objects. While coverage guidance would reward the fuzzer for triggering the implementation for each of the operations the first time, there would be no additional reward for combining them into a single data flow. Similarly, once the fuzzer has triggered a callback mechanism (e.g. a valueOf callback or a Proxy trap) once, it will likely not be rewarded for triggering the same callback mechanism in a different context (e.g. a different builtin), although that could lead to interesting bugs.

There are a number of possible solutions to this problem:

* Design an alternative guidance metric as replacement or complement to pure code coverage which steers the fuzzer towards bugs that the existing metric has difficulties reaching. This metric could for example attempt to combine coverage feedback with some form of dataflow analyses to reward the fuzzer for triggering multiple distinct features on the same dataflow. This is a topic for future research.
* Seed the fuzzer from proof-of-concept code or regression tests for old vulnerabilities to find remaining bugs that can be triggered by somewhat similar code. This is possible by using the [FuzzIL compiler](https://github.com/googleprojectzero/fuzzilli/tree/main/Sources/Fuzzilli/Compiler) discussed above to compile existing JavaScript code into a FuzzIL corpus. This approach is inherently limited to finding bugs that are at least somewhat similar to past vulnerabilities.
* Improve the code generation infrastructure and use it to create new programs from scratch, possibly targeting specific bug types or components of the target JavaScript engine. The remainder of this document discusses this approach and the HybridEngine that implements it.


## The HybridEngine
Implementation: [HybridEngine.swift](https://github.com/googleprojectzero/fuzzilli/blob/main/Sources/Fuzzilli/Engines/HybridEngine.swift) (--engine=hybrid)

The central idea behind the HybridEngine is to combine code generation with the existing mutations and the splicing mechanism. This achieves a number of things:

* It allows for manual fuzzer guidance by configuring the shape and aspects of
  the generated programs (for example to stress certain areas of the JavaScript
  engine or specific APIs).
* It allows the pure code generator to be stay fairly simple and instead rely
  on the mutators to make the generated code more interesting or more correct.
  In particular, the FixupMutator is specifically designed to aid the
  HybridEngine in generating correct and meaningful programs.
* It prevents over-specialization and improves the diversity of the emitted
  code as the mutations (mainly the input and operation mutations) are
  completely random and unbiased (for example, they ignore any type
  information). As such, they will also frequently result in semantically
  invalid samples.
* It enables the code generation engine to "learn" interesting code fragments
  as these will be added to the corpus (due to coverage feedback) and then used
  for splicing. Due to this, code coverage feedback is still used even in a
  generative fuzzing mode.

In contrast to the MutationEngine, the HybridEngine mostly lacks coverage guidance. As such, it needs to solve a number of problems in a different way:

### 1. The Correctness Problem
As the mutation engine reverts invalid mutations (those that cause a runtime exception to be raised), code generation during mutation can be somewhat aggressive and therefore lead to more invalid samples. However, when generating entire programs from scratch, the correctness rate of the generated samples is much more important. As such, the code generators needs to be careful not to generate invalid code. This is achieved in a number of ways:

1. Code generators should select input variables of the correct types. For example, a generator that emits a function call should ensure that the chosen variable contains a callable value.

2. Code generators can use guarded instructions (or explicit try-catch blocks) when they cannot prove that no exception will be thrown at runtime (this may happen for a number of reasons, including that no variable of the required type is currently available). As discussed above, both the FixupMutator and the Minimizer will take care of removing unecessary guards.

3. There are a few other ad-hoc mechanisms that try to prevent common sources of invalid programs. For example, the ProgramBuilder supports a "recursion guard" which prevents trivial recursion.

### 2. The Meaningfulness Problem
Consider the following code:

```javascript
let v0 = ...;
let v1 = v0 / {};
```

While semantically valid (no exception is thrown at runtime), the code is mostly semantically meaningless as it only results in the NaN (not-a-number) value. As such, the output state space of this code is one, no matter the actual value of `v0`. Other examples of (mostly) meaningless operations include loading or deleting non-existing properties (which will always result in the undefined), performing any kind of mathematical operations (arithmetic operators or Math functions) on objects that don’t have custom toPrimitive conversion operators or on non-numerical strings, passing values of incorrect types as arguments to builtin functions, or storing properties on non-objects.

Ideally, "meaningless" would likely be defined as always resulting in the same internal state transitions of the engine regardless of input types and surrounding code. As that is hard to measure, Fuzzilli's interpretation of the terms is mostly a vague approximation, and so certain operations that Fuzzilli would regard as meaningless will actually cause some intersting behaviour in some engines. However, due to the performed mutations, "meaningless" code will still be generated (just not with an unreasonably high probability), hopefully allowing related bugs to be found.

In the mutation engine, code coverage in combination with the minimizer effectively solves this problem: meaningless code fragments do not trigger any new coverage and will thus be removed by the minimizer before being included in the corpus. As such, the corpus contains mostly meaningful code fragments, and so the generated code is also mostly meaningful.

However, a generative engine doesn’t have the luxury of relying on coverage feedback (apart from splicing). As such, the main design goal of the code generation engine is to strive to generate meaningful code with a high frequency, where a loose definition of meaningful is that for given input types, the output can have different values depending on the input values. In practice, this for example means that a CodeGenerator that performs bitwise operations should require numerical input values instead of completely arbitrary ones:

```swift
CodeGenerator("BitOp", inputs: .preferred(.number, .number)) { b, lhs, rhs in
    b.binary(lhs, rhs, with: chooseUniform(from: allBitwiseOperators))
}
```

Further, the FixupMutator is (eventually) meant to also address this problem by detecting meaningless operations at runtime and changing them to be more meaningful.

### 3. The Lookahead Problem
Consider the case where Fuzzilli generates a function definition (e.g. through the PlainFunctionGenerator):

```javascript
function foo(v4, v5) {
    ...
}
```

Here, the types of v4 and v5 are unknown when the function body is generated as they could only be observed by the JSTyper when the function is later called. However, if the arguments are simply set to the unknown type (.anything in FuzzIL’s type system), then the code in the body would not be able to use them meaningfully.

The solution thus is to generate a random but non-trivial function signature every time a function is generated. For example, in pseudocode:

```javascript
function foo(v4: Number, v5: JSArray) -> JSArray {
    // Can make meaningful use of v4 and v5 here
    ...;
}
```

With that, the code in the body can use the parameters meaningfully, and its return value can also be used. The function will have its signature stored in its type (as builtin functions and methods do as well) and so any calls to it generated in the future will attempt to obtain argument values of the correct type. When the signature is generated, the currently available variables are taken into account such that the probability of generating a signature which cannot be satisfied is very low.

A related question is how to deal with custom object types, for example to generate code like:

```javascript
function foo(v3) {
    return v3.a.b.c;
}
```

For this to be possible, Fuzzilli must not only know about the type of v3 but also about the type of its properties.

This can similarly be solved by generating a number of custom object types up front and using those in the generator. For example, the following type might be used for v3 above:

```
v3 = .object("ObjType1", [
    .a: .object("ObjType2", [
        .b: .object("ObjType3", [
            .c: .integer
        ])
    ])
])
```

For this to work, code generators that generate objects or property stores have to obey these property types.

### Program Templates
As previously discussed, there needs to be some guidance mechanism to direct the fuzzer towards specific areas of the code. In the HybridEngine, this is achieved through ProgramTemplates: high-level descriptions of the structure of a program from which concrete programs are then generated. This effectively restricts the search space and can thus find vulnerabilities more efficiently.

An example for a ProgramTemplate is shown next.

```swift
ProgramTemplate("JITFunction") { b in
    // Start with a random prefix and some random code.
    b.buildPrefix()
    b.build(n: 5)

    // Generate a larger function and a signature for it
    let f = b.buildPlainFunction(with: b.randomParameters()) { args in
        assert(args.count > 0)
        b.build(n: 30)
        b.doReturn(b.randomVariable())
    }

    // Trigger JIT optimization
    b.buildRepeatLoop(n: 100) { _ in
        b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
    }
```

This fairly simple template aims to search for JIT compiler bugs by generating a random function, forcing it to be compiled, then calling it again with different arguments.

### Example
The following is a walkthrough of how the HybridEngine may generate a program based on the template above. Note that not all CodeGenerators have been migrated to work well with the HybridEngine (e.g. by emitting guarded instruction if necessary) as that is still work-in-progress.

#### 1. Prefix code generation
The template starts out by generating a small "prefix" via the `b.buildPrefix()` method. A prefix is simply a piece of code whose purpose is to create some variables for use by subsequent code. It is usually recommended to start out with such a prefix, as it ensures that CodeGenerators have visible variables to use as inputs. Under the hood, prefix generation performs code generation but with only a small list of code generators marked as "value generators". These must always generate new variables and must not fail. The result may be a piece of code such as
```
v0 <- LoadInt '42'
v1 <- LoadInt '1337'
v2 <- LoadString 'foo'
```

#### 2. Random code generation
The next part of the template simply generates a couple of random instructions using the main code generation API: `ProgramBuilder.build(n:)`. For code generation, the ProgramBuilder will repeatedly pick random CodeGenerators and run them until at least `n` instructions have been generated. An example CodeGenerator could looks as follows:

```swift
CodeGenerator("BinOp", inputs: .preferred(.number, .number)) { b, lhs, rhs in
    let needGuard = b.type(of: lhs).MayBe(.bigint) || b.type(of: rhs).MayBe(.bigint)
    b.binary(lhs, rhs, with: chooseUniform(from: allBinaryOperators), guard: needGuard)
}
```

Note how the generator is careful to generate both correct _and_ meaningful code, while also not being unreasonably strict about its input requirements. It does so by stating that it "prefers" to receive numbers as inputs (meaning that it should be called with numbers if there are available variables, but can also be called with variables of different types), then checking if one of the inputs may be BigInts (in which case there would likely be a runtime exceptions: "TypeError: Cannot mix BigInt and other types, use explicit conversions"), and if so marking the operation as guarded (resulting in a try-catch being used at runtime).

Used in this context, the generator may be invoked using `v0` and `v1`:

```
v3 <- Binary v0, '*', v1
```

As the types of both inputs are statically known to not be BigInts, no guarding is necessary.

At this point, only one new instruction has been generated, and so code generation would continue. However, in the interest of brevity, for this example we will stop code generation here and move on to the next part of the template.

#### 3. Function generation
The next part of the template is responsible for generating a random function. For that, the first step is to generate a random signature using the `ProgramBuilder.randomParameters` API. This will look at the existing variables and their types and select a signature based on them. This way, there is a high chance that fitting argument values can be found later on. In this specific case, it could come up with a signature such as `[.string, .int]` as there are existing variables of both types. Note that the signature does not yet include the return value type. That will only be computed at the end of the function definition, depending on the `Return` statements generated inside the function body.

After generating the signature, the template creates the function and fills its body using the code generation machinery. This time, we will use the following three code generators:

```swift
CodeGenerator("BuiltinGenerator") { b in
    b.loadBuiltin(b.randomBuiltin())
},

CodeGenerator("FunctionCallGenerator", inputs: .preferred(.function())) { b, f in
    let arguments = b.randomArguments(forCalling: f)
    let needGuard = b.type(of: f).MayNotBe(.function())  // Technically would also need a guard if the argument types didn't match the signature
    b.callFunction(f, withArgs: arguments, guard: needGuard)
},

CodeGenerator("ComputedPropertyAssignmentGenerator", inputs: .preferred(.object())) { b, obj in
    let propertyName = b.randomVariable()
    let value = b.randomVariable()
    let needGuard = b.type(of: obj).MayBe(.nullish)
    b.setComputedProperty(propertyName, of: obj, to: value, guard: needGuard)
},
```

When running the first generator, the `ProgramBuilder.randomBuiltin` API will consult the static environment model to find an available builtin. In this case, the environment model may contain the following builtin: `bar: .function([] => .anything)`, which is then choosen. Next, code generation may select the  `FunctionCallGenerator`. As it states that it would like a `.function()` as argument, the ProgramBuilder would (likely) select the previously loaded builtin. As its signature is known, no argument values are selected for the call and the return value is typed as `.anything`. Finally, code generation may pick the `ComputedPropertyAssignmentGenerator`. As there is currently no value of type `.object()` available, the return value of the function call would (likely) be selected as it has type `.anything`. This way, there is al least a chance that the value will be an object at runtime. As it cannot be ruled out that the value is not "nullish" (`null` or `undefined`), in which case a runtime exception would be raised, the code generator marks the operation as guarded. Putting everything together, the following code is generated for the function:

```
v4 <- BeginPlainFunction -> v5, v6
    v7 <- LoadBuiltin 'bar'
    v8 <- CallFunction v7, []
    SetComputedProperty v8, v5, v6 (guarded)
    Return v8
EndPlainFunction
```

#### 4. Putting it all together
The remainder of the template simply generates a loop to call the function generated in step 3. Typically, the function should be called again a few more times with different arguments and possibly after executing some more randomly generated code. To keep this example short, these steps are skipped here, however.

Lifted to JavaScript (with expression inlining), the generated code would now be:
```js
function f4(a5, a6) {
    let v8 = bar();
    try { v8[a5] = a6; } catch {}
    return v8;
}
for (let v9 = 0; v9 < 100; v9++) {
    f6("foo", 42 * 1337);
}
```

After generation, the sample will be mutated further. As the FixupMutator is especially useful for the HybridEngine, it is always used as the first mutator to "refine" the generated program. In this case, the mutator may discover that the try-catch guard is not needed (if it never triggers at runtime) and can therefore be removed, resulting in the final ("refined") program:

```js
function f4(a5, a6) {
    let v8 = bar();
    v8[a5] = a6;
    return v8;
}
for (let v9 = 0; v9 < 100; v9++) {
    f6("foo", 42 * 1337);
}
```

The subsequent mutations may then change the generated program in all sorts of interesting (and less interesting) ways.

### Code Generation + Mutations: The HybridEngine
The HybridEngine combines the code generation engine with the existing mutators. For that, it first selects a random ProgramTemplate, then generates a program from it, using the code generation engine as discussed previously. If the generated program is valid, it is further mutated a few times, using the algorithm that is also used by the Mutationengine.

The high-level algorithm used by the hybrid engine is summarized by the image below.

![Hybrid Fuzzing Algorithm](images/hybrid_engine.png)

There are different ways in which the HybridEngine can be used. These are discussed next.

### Application: Component Fuzzing
Through ProgramTemplates, the fuzzer can be directed towards major components of the engine, such as the JIT compiler. This kind of template likely requires fairly little effort apart from a high-level understanding of the targeted code (and possibly past bugs in it).

### Application: Patch Correctness and Variant Fuzzing
Another application of the HybridEngine is to search for variants of previous bugs.

A good example of this technique is the V8MapTransition template. This template searches for variants (and attempts to verify the correctness of the patch) for [CVE-2020-16009](https://bugs.chromium.org/p/project-zero/issues/detail?id=2106). The idea is simply to restrict the code generation engine to a small set of JavaScript features, namely object literals, property loads and stores, and function definitions and calls, in order to reduce the search space. This template succeeded in triggering the original vulnerability again within a few hundred million executions, thus demonstrating that the technique is feasible.

### Application: Targeted Fuzzing
This application is similar to the previous one, except that it doesn’t start from an existing bug. Instead, a human, either a security researcher or a developer first has to identify a specific feature of the target engine that might be susceptible to complex bugs, then develop a template to stress this component as good as possible.

In contrast to the first application, this kind of template requires a fairly deep understanding of the targeted source code area, for example in order to determine which kinds of code fragments need to be generated and which ones don’t. On the other hand, it should be significantly more efficient.

### MutationEngine vs. HybridEngine
The section briefly compares the two engines featured in Fuzzilli.

MutationEngine | HybridEngine
---------------|--------------
Follows a generic guidance algorithms and requires almost no manual tuning to generate interesting JavaScript code | Requires manual guidance, in the form of ProgramTemplates and CodeGenerators
There is little room for control over the generated samples since they are mostly determined by the coverage feedback. Possible ways to influence the code include the CodeGenerators and their relative weights, the Mutators, and the aggressivity of the minimizer | Allows a great amount of control over the generated code, both over the high level structure (for example, one function that is being JIT compiled, then called a few times) as well as over low-level code fragments through CodeGenerators
Able to find vulnerabilities that are "close" to samples trigger new coverage (and so are added to the corpus), but likely struggles to find bugs that are not. The latter probably includes bugs that require complex state manipulation through multiple distinct code paths | Able to find bugs that are "close" to one of the used ProgramTemplates, which can either come from past bugs, from developers that want to test certain areas, or from auditors that want to test a complex are of the codebase

As the engines complement each other, it can be desirable to run both engines in the same fuzzing session. At least in theory, the two engines should also be able to benefit from each other: the mutation engine can further mutate samples originating from the HybridEngine, while the HybridEngine benefits (through splicing) from a better Corpus built by the MutationEngine. For that reason, the [MultiEngine](https://github.com/googleprojectzero/fuzzilli/blob/main/Sources/Fuzzilli/Engines/MultiEngine.swift) (--engine=multi) allows using both engines in one fuzzing session, and allows controlling roughly how often each engine is scheduled.



