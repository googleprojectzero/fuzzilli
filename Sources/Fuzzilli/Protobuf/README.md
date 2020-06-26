# Fuzzilli Protobuf Definitons

Install the protoc compiler and the swift plugin:

    brew install swift-protobuf

Then generate the swift files:

    protoc --swift_opt=Visibility=Public --experimental_allow_proto3_optional --swift_out=. program.proto operations.proto typesystem.proto sync.proto
