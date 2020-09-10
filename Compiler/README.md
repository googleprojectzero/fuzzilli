This compiler takes in JS files, and produces fuzzilli IL protobufs, to be used as input to the fuzzer.

Dependencies
This project uses ocaml-protoc for protobufs, and flow_parser for parsing JS
Installing flow_parser is a bit non-standard. I followed the steps here: https://discuss.ocaml.org/t/library-to-parse-javascript-in-opam/5775/6

How to install

Install opam and ocaml via the appropriate steps for your system

Dev was done on Ocaml 4.10 on Ubuntu 20.04, with VSCode and this plugin: https://marketplace.visualstudio.com/items?itemName=freebroccolo.reasonml
    Left as a reference due to all the pains I had getting this to work...

Pin and install flow_parser via
    `opam pin add flow_parser https://github.com/facebook/flow.git`

Find the opam file for flow_parser on your system. Mine was at `~/.opam/default/.opam-switch/sources/flow_parser/flow_parser.opam`
    Add that value to package.json, under resolutions

Install esy (https://esy.sh/), which requires npm

Run esy to install and build everything else
    `esy install`
    `esy build`

`esy run-script build-pbs` will build the protobuf files, and put them into ./src/proto

`esy x test` to run tests
