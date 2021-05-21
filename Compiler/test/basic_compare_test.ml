open Program_types
open Compiler.ProgramBuilder

let input = 
"const v0 = 1 == 1;
const v1 = 1 === 1;
const v2 = 2 >= 2;
const v3 = 7 < 9;"

let correct = 
    let builder = init_builder false false false in
    let int_1, load_1 = build_load_integer 1L builder in
    let int_1_2, load_1_2 = build_load_integer 1L builder in
    let _, equal_inst = build_compare_op int_1 int_1_2 Equal builder in
    let int_1_3, load_1_3 = build_load_integer 1L builder in
    let int_1_4, load_1_4 = build_load_integer 1L builder in
    let _, strict_equal_inst = build_compare_op int_1_3 int_1_4 StrictEqual builder in
    let int_2_0, load_2_0 = build_load_integer 2L builder in
    let int_2_1, load_2_1 = build_load_integer 2L builder in
    let _, greater_eq_inst = build_compare_op int_2_0 int_2_1 GreaterThanEqual builder in
    let int_7, load_7 = build_load_integer 7L builder in
    let int_9, load_9 = build_load_integer 9L builder in
    let _, less_than_inst = build_compare_op int_7 int_9 LessThan builder in
    let res = [load_1; load_1_2; equal_inst; load_1_3; load_1_4; strict_equal_inst; load_2_0; load_2_1; greater_eq_inst; load_7; load_9; less_than_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "basic_compare_test" correct prog 