open Program_types
open Compiler.ProgramBuilder

let input = 
"const v0 = 5;
v0++;
--v0;"

let correct = 
    let builder = init_builder false false false in
    let int_5, load_int_5 = build_load_integer 5L builder in
    let _, post_inc = build_unary_op int_5 PostInc builder in
    let _, pre_inc = build_unary_op int_5 PreDec builder in
    let res = [load_int_5; post_inc; pre_inc] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "update" correct prog 