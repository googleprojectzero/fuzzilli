# Type determination

Fuzzilli implements its own [typesystem](https://github.com/googleprojectzero/fuzzilli/blob/master/Sources/Fuzzilli/FuzzIL/TypeSystem.swift)
used for finding variables that satisfy a given type requirement and for determining which
properties and methods are available on a given variable.
Imprecise type information for variables can lead to the generation of invalid JavaScript which is then rejected by the engine.

There are currently 2 ways Fuzzilli can determine the type of a variable:
   1. Statically, via the [AbstractInterpreter](https://github.com/googleprojectzero/fuzzilli/blob/master/Sources/Fuzzilli/FuzzIL/AbstractInterpreter.swift) (used by default)
This is fast but fairly imprecise as it only approximates JavaScript execution semantics.
Fuzzilli uses it when there is no runtime type information too.

   2. Dynamically through [runtime types collection](https://github.com/googleprojectzero/fuzzilli/blob/0f26cb9ec248426a140acc333537c797a95c42f8/Sources/Fuzzilli/Fuzzer.swift#L374)
This is precise but somewhat slow. It is enabled through the `--collectRuntimeTypes` 
command-line flag.

## Abstract Interpreter
The interpreter attempts to determine the runtime types of variables by abstractly interpreting a program.
For that, it relies on simply semantic rules, such as that the + operator will always result in a primitive type,
and on the environment to for example determine property types of known objects, the types of builtins,
and signatures of methods and builtin functions.
The [implementation](https://github.com/googleprojectzero/fuzzilli/blob/master/Sources/Fuzzilli/FuzzIL/AbstractInterpreter.swift)
is designed to be fast and simple, being only a few hundred lines of code.

## Runtime types collection
The basic idea is that instead of statically inferring types during program construction, Fuzzilli can gather types during execution.
For that, the lifter injects a call to the [updateType](https://github.com/googleprojectzero/fuzzilli/blob/0f26cb9ec248426a140acc333537c797a95c42f8/Sources/JS/initTypeCollection.js#L109)
function after each statement in the original script where it is reasonable to collect types.
This function determines the type of the variable created/changed by the last statement and
stores it in a type collection data structure.
After execution of the original script is completed, the script sends the structure with gathered types
back to Fuzzilli via a dedicated output channel.

Unfortunately, running `updateType` after each statement would significantly slow down the fuzzer and
thus we cannot afford collecting runtime types for every program nor every instruction.
Instead, Fuzzilli runs it only on [interesting programs](https://github.com/googleprojectzero/fuzzilli/blob/0f26cb9ec248426a140acc333537c797a95c42f8/Sources/Fuzzilli/Fuzzer.swift#L421)
which are added to the corpus afterwards.
During mutation, Fuzzilli keeps types for unchanged instructions and adjusts types for mutated ones.

Fuzzilli does not gather function signatures as it makes no sense to capture the types of parameters
and return values as they are generally specific to a single program.

### Implementation
Implementation basically consists of 4 main parts.

1. **The lifter instruments the generated JavaScript code to perform the type collection**

    Firstly script defines [here](https://github.com/googleprojectzero/fuzzilli/blob/master/Sources/JS/helpers.js)
some constants and backup builtin functions for later use, because generated JS script can change them later.
Then there are reimplemented basic parts of [Fuzzilli typesystem](https://github.com/googleprojectzero/fuzzilli/blob/0f26cb9ec248426a140acc333537c797a95c42f8/Sources/JS/initTypeCollection.js#L14) and
actual [type determination](https://github.com/googleprojectzero/fuzzilli/blob/0f26cb9ec248426a140acc333537c797a95c42f8/Sources/JS/initTypeCollection.js#L69) implementation.
If a variable appears in a statement executed several times (e.g. loop)
we consider its type as a union of all possibilities.
If a variable appears in multiple statements we capture its type for each statement separately.

    Then the lifter emits a [function](https://github.com/googleprojectzero/fuzzilli/blob/0f26cb9ec248426a140acc333537c797a95c42f8/Sources/Fuzzilli/Lifting/JavaScriptLifter.swift#L565)
triggering type collection for the variable changed in the last statement if the `collectTypes` option is enabled.
The lifter uses `InlineOnlyLiterals` policy to collect as many variable types as possible,
but still avoids behavior change when not inlining at all
(e.g. indirect [eval](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/eval#Description)).
Detecting type of literals is easy and can be done by `AbstractInterpreter`.

    At the end JS script [prints](https://github.com/googleprojectzero/fuzzilli/blob/master/Sources/JS/printTypes.js)
variable types for every instruction to fuzzilli output in JSON format.

2. **Fuzzilli parses the type data and attaches it to the Program class.**

    Generated protobuf classes are able to parse needed Type class from JSON and store it in Program class.

3. **Adopting types after mutations**

    When an instruction is mutated, we discard the output type. For unchanged instructions we keep all the types.

    There are more strategies on how to adopt types after mutations, but currently it seems there is not much to gain with more complicated strategies. We may reevaluate this in future.

4. **Statistics**

    From time to time it happens runtime type collection is not successful.
[Here](https://github.com/googleprojectzero/fuzzilli/blob/0f26cb9ec248426a140acc333537c797a95c42f8/Sources/Fuzzilli/Modules/Statistics.swift#L81)
Fuzzilli counts the number of failures and time-outs and prints them along with other useful statistics.

### Limitations
After all this there are still some caveats, which we should be aware of:

*  Type collection of large objects is really slow and if there are many of them in the generated script, type collection will almost certainly run out of time. It is a very similar case when we collect type of single large object in a long loop.

*  We [skip](https://github.com/googleprojectzero/fuzzilli/blob/0f26cb9ec248426a140acc333537c797a95c42f8/Sources/JS/initTypeCollection.js#L97)
long typed arrays type collection as there are not many interesting properties and we can detect them

  ```
  const v0  = new Uint8Array(1000000) // fast operation, initialized lazily
  updateType(0, v0) // slow operation iterating over all array
  ```

*  Rarely it happens script changes getters of some variables which can change behavior
of program execution inside the `updateType` function.
This can lead to any behavior (failure, infinite cycle, wrong type)

*  Generated script can change Object/Array prototype.
Collection script uses these 2 structures when collecting types and doesn't backup the whole prototype.
Again this can lead to unexpected behavior.

  ```
  const v0 = []
  const v1 = v0.__proto__
  v1.push = 42 // updateType uses pushing to array and now it is not callable
  ```

*  We always gather only properties accessible by dot notation

*  We update the type only of variables changed by the last statement directly.
   With shared objects like prototypes can happen more variables are changed (and so its type).
   We do not handle this for now.

  ```
  const v0 = [1]
  updateType(0, v0)
  const v1 = [2]
  updateType(1, v1)
  const v2 = v0.__proto__
  updateType(2, v2)
  v2.concat = 42 // This changes type of all v0, v1, v2 variables
  ```

  It can happen generated script changes builtins which are statically typed
  and we miss this change.

  ```
  Math.max = 42;
  ```

## Cooperation of runtime types information & AbstractInterpreter

Both approaches have their advantages and disadvantages, so to answer queries about type information
we have to combine information from both sources to return the best answer.
We cannot afford to collect runtime type on every instruction, but some instructions can be handled by the interpreter pretty well.
Consider the following code:

```
const v0 = {a:1}
v0.b = 2
```

We see that the second instruction does not change `v0` type much and it is time inefficient to collect its type again.
But statically it is easy to just add `b` as property to the type of `v0`.

Our implementation [injects](https://github.com/googleprojectzero/fuzzilli/blob/0f26cb9ec248426a140acc333537c797a95c42f8/Sources/Fuzzilli/Core/ProgramBuilder.swift#L357)
runtime type information to interpreter whenever available,
so interpreter can correctly infer type at instructions where runtime type is not available.

In this setup it is enough to collect runtime types only on new variable definitions or
significant changes to variable type (e.g. `__proto__` property changes).
