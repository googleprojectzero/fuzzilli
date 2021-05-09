open Program_types
open Compiler.ProgramBuilder

let input = 
"let v0 = 0;
const v1 = 5;
v0 = v1 + 1; 
"

let correct = 
    let builder = init_builder false false false in
    let int_0, load_int_0 = build_load_integer 0L builder in
    let int_5, load_int_5 = build_load_integer 5L builder in
    let int_1, load_int_1 = build_load_integer 1L builder in
    let bin_temp, bin_inst = build_binary_op int_5 int_1 Plus builder in
    let reassign_inst = build_reassign_op int_0 bin_temp builder in
    let res = [load_int_0; load_int_5; load_int_1; bin_inst; reassign_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "exp_statement" correct prog
    