open Program_types
open Compiler.ProgramBuilder

let input = 
"let v0 = 1;
v0 += 10;
let v1 = 2;
v1 -= 20;"

let correct = 
    let builder = init_builder false false false in
    let int_1, load_int_1 = build_load_integer 1L builder in
    let int_10, load_int_10 = build_load_integer 10L builder in
    let add_temp, add_inst = build_binary_op int_1 int_10 Plus builder in
    let reassign_op = build_reassign_op int_1 add_temp builder in
    let int_2, load_int_2 = build_load_integer 2L builder in
    let int_20, load_int_20 = build_load_integer 20L builder in
    let sub_temp, sub_inst = build_binary_op int_2 int_20 Minus builder in
    let reassign_op2 = build_reassign_op int_2 sub_temp builder in
    let res = [load_int_1; load_int_10; add_inst; reassign_op; load_int_2; load_int_20; sub_inst; reassign_op2] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "sugared_assignment" correct prog 