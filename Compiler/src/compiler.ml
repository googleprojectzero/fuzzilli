
(* Translate Interface  *)
let flow_ast_to_inst_list = Translate.flow_ast_to_inst_list

(* Util Interface *)
let print_ast_statement_list = Util.print_statement_list

let string_to_flow_ast = Util.string_to_flow_ast

let write_proto_obj_to_file = Util.write_proto_obj_to_file

let inst_list_to_prog = Util.inst_list_to_prog

let pp_instruction = Program_pp.pp_instruction

(* Give the test interface access to the protobufs *)
module Program_types = Program_types
module Operations_types = Operations_types
module Typesystem_types = Typesystem_types