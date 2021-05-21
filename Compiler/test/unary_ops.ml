open Program_types
open Compiler.ProgramBuilder

let input = 
"const v0 = !true;
const v1 = !false;
const v2 = !v0;
const v3 = ~5;"

let correct = 
    let builder = init_builder false false false in
    let true_temp, load_true = build_load_bool true builder in
    let not_temp, not_inst_1 = build_unary_op true_temp Not builder in
    let false_temp, load_false = build_load_bool false builder in
    let _, not_inst_2 = build_unary_op false_temp Not builder in
    let _, not_inst_3 = build_unary_op not_temp Not builder in
    let int_5, load_int_5 = build_load_integer 5L builder in
    let _, bit_not_inst = build_unary_op int_5 BitNot builder in
    let res = [load_true; not_inst_1; load_false; not_inst_2; not_inst_3; load_int_5; bit_not_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "unary_ops" correct prog 