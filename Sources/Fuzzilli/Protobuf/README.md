# Fuzzilli Protobuf Definitons

Install the protoc compiler and the swift plugin:

    brew install swift-protobuf

Then generate the swift files:

    protoc --swift_opt=Visibility=Public --swift_out=. program.proto operations.proto sync.proto

If you have added a new IL operation in Sources/Fuzzilli/FuzzIL/Opcodes.swift,
you can use the `gen_programproto.py` file to auto-generate the `program.proto`
file from within this directory:

    python3 ./gen_programproto.py
