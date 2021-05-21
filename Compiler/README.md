# Overview

Originally written by [William Parks](https://github.com/WilliamParks)

This compiler compiles a Javascript source file to the Fuzzilli intermediate language, encoded in a protobuf. This allows Fuzzilli to start execution from a large initial corpus.


This compiler was designed and tested on Ubuntu 20.04. See below for running in in Docker.

## Dependencies
This project uses ocaml-protoc for protobufs, and flow_parser for parsing JS.

- Installing flow_parser is unfortunately a bit non-standard. Development followed the process here to get the correct version: [Installing flow_ast](https://discuss.ocaml.org/t/library-to-parse-javascript-in-opam/5775/6).

- Pin and install flow_parser via
    `opam pin add flow_parser https://github.com/facebook/flow.git`

- Find the opam file for flow_parser on your system. Mine was at `~/.opam/default/.opam-switch/sources/flow_parser/flow_parser.opam`
    Add that value to package.json, under resolutions

- Install esy (https://esy.sh/), which requires npm

- Run esy to install and build
    
    `esy install`

    `esy build`

## Building Protobuf files

`esy run-script build-pbs` will build the Ocaml interface to the protobuf files found in the [Protobuf](Sources/Fuzzilli/Protobuf) directory, and will put the results in [src/proto](./src/proto)

## Testing

`esy x test` will run all the compiler tests, found in [test](./test). Currently, each one consists of a Javascript source snippet, and expected resulting fuzzil output. Note that these tests may be sensitive to changes in the Fuzzilli intermediate language.

## Running
Once successfully built, the compiler can be run with `esy x fuzzilli_compiler` or `./Compiler/_esy/default/build/default/bin/fuzzilli_compiler.exe`

## Useful compiler flags

    -ast
        Prints the abstract syntax tree produced by flow_ast. Useful for further compiler development
    -builtins
        Prints all Javascript identifiers the compiler has determined to be builtins
    -use-placeholder
        Replaces all unknown Javascript builtins with a call to a function named `placeholder`. This is a hack to increase the number of samples that execute successfully. `Placeholder` must then be defined in the Fuzzilli profile for the targeted engine.
    -v8-natives
        Flow_ast does not properly handle the syntax of v8 natives (example %PrepareFunctionForOptimization). With this flag enabled, the compiler will first scan the input file for a short list of natives specified in [util.ml](src/util.ml), and replace them with function calls to functions of the same name, without the leading `%`. Each function defined this way must then be implemented properly in the [V8 profile](Sources/FuzzilliCli/Profiles/V8Profile.swift).

## Docker

This compiler can also be run in Docker, using the following commands

Build the Docker image and run tests with `docker build -t compiler_builder .`

To copy the executable out of the docker container, use: 

 `docker create --name temp_container compiler_builder && docker cp temp_container:/home/builder/Compiler/fuzzilli_compiler.exe fuzzilli_compiler.exe && docker rm temp_container`

# Design

This compiler is implemented in a pair of passes over the Abstract Syntax Tree (AST) produced by `flow_ast`, one to do variable hoisting and the second to produce the output protobuf. The general design principle is to keep the compiler simple, avoiding any of the optimizations seen in a normal compiler (constant folding, etc.), nor trying to achieve quick compilation.

* [translate](./src/translate.ml) contains the compilation logic. It walks the AST, and calls both ProgramBuilder and VariableScope.
* [VariableScope](./src/VariableScope.ml) walks the AST and returns which functions and variables should be hoisted
* [ProgramBuilder](./src/Programbuilder.ml) produces individual instructions in the protobuf format, without compiler logic

## Loops
All loops are converted to `while` loops, where the conditional is a comparison against the integer `0`, and executed once before the loop, and at the end of each iteration.
This is best explained in the following example:

```javascript
for(let i = 0; i < 10; i++){
    foo(i);
}
```
becomes
```javascript
let i = 0;
let t1 = i < 10;
while(t1 != 0) {
    foo(i);
    i++;
    t1 = i < 10;
}
```

## Variable & Function Hoisting
The compiler implements a basic version of both variable and function hoisting. [VariableScope](./src/VariableScope.ml) determines which variables and functions require hoisting to meet the Fuzzilli static checks, and lifts those to the beginning of the function in which they are defined. It assumes that the whole program will be inserted into a `main` function, as currently implemented in each individual JS engine profile.

## Type Information
The compiler is designed to include minimal type information, intending Fuzzilli proper to collect type information itself. Values are based on the hardcoded values in [TypeSystem.swift](Sources/Fuzzilli/FuzzIL/TypeSystem.swift). The type information in the overall program protobuf is left empty. Function parameters are provided as `.anything` and return `.unknown`. The constants are defined in [ProgramBuilder](./src/Programbuilder.ml) as `unknown_type_int` and `anything_type_int`

## Known limitations/TODOs

* Improve variable hoisting (current implementation is likely only partially correct, proper scoping is likely incorrect)
* Implement the following, which may require changes to Fuzzilli proper
    - Template Literals
    - Classes
    - Spread (update Fuzzilli)
* Improve for/while loops. The current implementation makes all loops while loops, with a comparison against 0.
* Improve for-of/for-in loops. A large number of test cases have more complex left sides, while Fuzzilli only supports declaring/defining a new variable.
    - Example from a regression: for (a[i++].x in [])
* Add FuzzILTool, Javascript engine to compiler tests, to ensure the output is a valid Fuzzilli IL program, and lifts to valid Javascript
* Detect and properly handle global variables (e.g. g = 5 without var/let/const)
* `build_func_ops` in [ProgramBuilder](./src/Programbuilder.ml) should be simplified to move more compilation functionality into the translation functionality
* `With` statements are likely incorrect, check [tests/with.ml](./tests/with.ml) for an example
* [ProgramBuilder](./src/Programbuilder.ml) has hardcoded values for types in the protobuf, that need to match those in TypeSystem.swift
    * These could be expanded into a full type constructor, similar to what is in `TypeSystem.swfit`