open Program_types
open Compiler.ProgramBuilder

let input = 
"let a = 1 < 0 ? 2 : 3;"

let correct = 
    let builder = init_builder false false false in
    let int_0, load_int_0 = build_load_integer 0L builder in
    let int_1, load_int_1 = build_load_integer 1L builder in
    let int_0_2, load_int_0_2 = build_load_integer 0L builder in
    let compare_temp, compare_inst = build_compare_op int_1 int_0_2 LessThan builder in
    let begin_if_inst = build_begin_if compare_temp builder in
    let int_2, load_int_2 = build_load_integer 2L builder in
    let reassign_inst = build_reassign_op int_0 int_2 builder in
    let begin_else = build_begin_else builder in
    let int_3, load_int_3 = build_load_integer 3L builder in
    let reassign_inst2 = build_reassign_op int_0 int_3 builder in
    let end_if = build_end_if builder in
    let res = [load_int_0; load_int_1; load_int_0_2; compare_inst; begin_if_inst; load_int_2; reassign_inst; begin_else; load_int_3; reassign_inst2; end_if] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "ternary_test" correct prog 