This compiler takes in JS files, and produces fuzzilli IL protobufs, to be used as input to the fuzzer. This allows Fuzzilli to start execution from a large initial corpus.

## Installation 
Dependencies
This project uses ocaml-protoc for protobufs, and flow_parser for parsing JS.
Installing flow_parser is unfortunately a bit non-standard. Development followed the process here to get the correct version: [Installing flow_ast](https://discuss.ocaml.org/t/library-to-parse-javascript-in-opam/5775/6).

Pin and install flow_parser via
    `opam pin add flow_parser https://github.com/facebook/flow.git`

Find the opam file for flow_parser on your system. Mine was at `~/.opam/default/.opam-switch/sources/flow_parser/flow_parser.opam`
    Add that value to package.json, under resolutions

Install esy (https://esy.sh/), which requires npm

Run esy to install and build everything else
    `esy install`
    `esy build`

### Building Protobuf files

`esy run-script build-pbs` will build the Ocaml interface to the protobuf files found in the [Protobuf](Sources/Fuzzilli/Protobuf) directory, and put the results in [./src/proto](./src/proto)

### Testing

`esy x test` will run all the compiler tests, found in [./test](./test). Currently, each one consists of a Javascript source snippet, and expected resulting fuzzil output. Note that these tests may be sensitive to changes in the fuzzil format itself

## Running
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

## Known issues/TODOs
In no particular order

* Document how variable hoisting is done
* Document issues with Javascript samples that fail Fuzzilli's static checks
* Finish documenting compiler source
* Document issue with some JS samples taking a very long time to compile
* Implement an easy to use OCaml linter
* Verify others can easily get the compiler running
* Improve test suite, and consider integrating FuzzIlTool to verify samples in the reverse direction of the compiler
