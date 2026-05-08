# Fuzzilli Protobuf Definitons

Install the protoc compiler and the swift plugin:

    brew install swift-protobuf

Then generate the swift files:

    protoc --swift_opt=Visibility=Public --swift_out=. program.proto operations.proto sync.proto ast.proto

For ease-of-use and to ensure consistent usages of the swift-protobuf version, the easiest way is to run:

    Tools/presubmit.py --regenerate-proto

If you have added a new IL operation in Sources/Fuzzilli/FuzzIL/Opcodes.swift,
you can use the `gen_programproto.py` file to auto-generate the `program.proto`
file from within this directory. If you add instructions, you need to make sure
that they are called the same in operations.proto as they are called in the
Instruction.swift serialization code. Execute the following command to generate
`program.proto`:

    python3 ./gen_programproto.py
