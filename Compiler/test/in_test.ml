open Program_types
open Compiler.ProgramBuilder

let input = 
"const v0 = 10;
const v3 = [15,20];
const v4 = v0 in v3;
"

let correct = 
    let builder = init_builder false false false in
    let int_10, load_int_10 = build_load_integer 10L builder in
    let int_15, load_int_15 = build_load_integer 15L builder in
    let int_20, load_int_20 = build_load_integer 20L builder in
    let array_temp, create_array_inst = build_create_array [int_15; int_20] builder in
    let _, in_inst = build_in_op int_10 array_temp builder in
    let res = [load_int_10; load_int_15; load_int_20; create_array_inst; in_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "in_test" correct prog
    