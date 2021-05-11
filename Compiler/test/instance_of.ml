open Program_types
open Compiler.ProgramBuilder

let input = 
"const v0 = 1;
const v1 = 2;
const v2 = v1 instanceof v0;
"

let correct = 
    let builder = init_builder false false false in
    let int_1, load_int_1 = build_load_integer 1L builder in
    let int_2, load_int_2 = build_load_integer 2L builder in
    let _, instance_inst = build_instanceof_op int_2 int_1 builder in
    let res = [load_int_1; load_int_2; instance_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "instance_of" correct prog
    