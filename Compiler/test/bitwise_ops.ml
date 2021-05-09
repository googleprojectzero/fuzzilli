open Program_types
open Compiler.ProgramBuilder

let input = 
"const v0 = 1 | 2;
const v1 = 3 & 4;
"

let correct = 
    let builder = init_builder false false false in
    let temp_1, load_1_temp = build_load_integer 1L builder in
    let temp_2, load_2_temp = build_load_integer 2L builder in
    let _, or_inst = build_binary_op temp_1 temp_2 BitOr builder in
    let temp_3, load_3_temp = build_load_integer 3L builder in
    let temp_4, load_4_temp = build_load_integer 4L builder in
    let _, and_inst = build_binary_op temp_3 temp_4 BitAnd builder in
    let res = [load_1_temp; load_2_temp; or_inst; load_3_temp; load_4_temp; and_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "bitwise_ops" correct prog 