# Overview

This compiler compiles a Javascript source file to the Fuzzilli intermediate language, encoded in a protobuf. This allows Fuzzilli to start execution from a large initial corpus.

## Running the compiler natively

This compiler was designed and tested on Ubuntu 20.04. See below for running this in Docker

### Dependencies
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

### Building Protobuf files

`esy run-script build-pbs` will build the Ocaml interface to the protobuf files found in the [Protobuf](Sources/Fuzzilli/Protobuf) directory, and will put the results in [./src/proto](./src/proto)

### Testing

`esy x test` will run all the compiler tests, found in [./test](./test). Currently, each one consists of a Javascript source snippet, and expected resulting fuzzil output. Note that these tests may be sensitive to changes in the Fuzzilli intermediate language.

### Running
Once successfully built, the compiler can be run with `esy x fuzzilli_compiler` or `./Compiler/_esy/default/build/default/bin/fuzzilli_compiler.exe`

### Useful compiler flags

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

## Compiler TODOs

    - Implement variable hoisting properly (current implementation is only partially correct)
    - Implement the following, which may require changes to Fuzzilli proper
        - Template Literals
        - Classes
        - Spread (update Fuzzilli)
    - Improve for/while loops. The current implementation makes all loops while loops, with a comparison against 0.
    - Add FuzzILTool, Javascript engine to compiler tests, to ensure the output is a valid Fuzzilli IL program, and lifts to valid Javascript
