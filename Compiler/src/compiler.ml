
(* Translate an ast to a list of instructions  *)
let flow_ast_to_inst_list = Translate.flow_ast_to_inst_list

(* Util Interface *)
let print_ast_statement_list = Util.print_statement_list

(* Run the flow_ast parser *)
let string_to_flow_ast = Util.string_to_flow_ast

(* Output a generated Protobuf*)
let write_proto_obj_to_file = Util.write_proto_obj_to_file

(* Wrap a list of instructions in the program structure *)
let inst_list_to_prog = Util.inst_list_to_prog

(* Pretty print support *)
let pp_instruction = Program_pp.pp_instruction

let init_test_builder = ProgramBuilder.init_builder false false false

(* Give the test interface access to the protobufs *)
module Program_types = Program_types
module Operations_types = Operations_types
module Typesystem_types = Typesystem_types

(* Make ProgramBuilder available to our test suite*)
module ProgramBuilder = ProgramBuilder