#!/bin/sh
ocaml-protoc -I ../Sources/Fuzzilli/Protobuf/ ../Sources/Fuzzilli/Protobuf/operations.proto -ml_out ./src/proto
ocaml-protoc -I ../Sources/Fuzzilli/Protobuf/ ../Sources/Fuzzilli/Protobuf/program.proto -ml_out ./src/proto
ocaml-protoc -I ../Sources/Fuzzilli/Protobuf/ ../Sources/Fuzzilli/Protobuf/typesystem.proto -ml_out ./src/proto
