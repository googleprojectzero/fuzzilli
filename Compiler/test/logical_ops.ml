open Program_types
open Compiler.ProgramBuilder

let input = 
"const v0 = 1 || 2;
const v1 = 3 && 4;"

let correct = 
    let builder = init_builder false false false in
    let int_1, load_int_1 = build_load_integer 1L builder in
    let int_2, load_int_2 = build_load_integer 2L builder in
    let _, or_inst = build_binary_op int_1 int_2 LogicalOr builder in
    let int_3, load_int_3 = build_load_integer 3L builder in
    let int_4, load_int_4 = build_load_integer 4L builder in
    let _, and_inst = build_binary_op int_3 int_4 LogicalAnd builder in
    let res = [load_int_1; load_int_2; or_inst; load_int_3; load_int_4; and_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "Logical_ops" correct prog 