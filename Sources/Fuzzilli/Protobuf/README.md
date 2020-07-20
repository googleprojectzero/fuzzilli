# Fuzzilli Protobuf Definitons

Install the protoc compiler and the swift plugin:

    brew install swift-protobuf

Then generate the swift files:

    protoc --swift_opt=Visibility=Public --swift_out=. program.proto operations.proto typesystem.proto sync.proto
