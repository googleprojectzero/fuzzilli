# Parser

Simple JavaScript parser based on babel.js to parse JavaScript code into the protobuf-based AST format used by the FuzzIL compiler.

## Usage

Make sure node.js is installed and in the $PATH. Then install the parser's dependencies: `npm i`. The parser can then be invoked manually as follows: `node parser.js ../../Protobuf/ast.proto code.js output.ast.proto` and will produce an AST as a protobuf. However, the parser is automatically invoked by the FuzzIL compiler, so there is usually no need to run it manually.
