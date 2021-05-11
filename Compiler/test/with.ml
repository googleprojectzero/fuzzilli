open Program_types
open Compiler.ProgramBuilder

let input = 
"let v0 = 10;
let v4 = 13;
const v2 = [12];
with (v2) {
    const v3 = 0.0;
    const v9 = v0 - v4;
}"


(* TODO: This likely is incorrect *)
let correct = 
    let builder = init_builder false false false in
    let int_10, load_int_10 = build_load_integer 10L builder in
    let int_13, load_int_13 = build_load_integer 13L builder in
    let int_12, load_int_12 = build_load_integer 12L builder in
    let arr_temp, create_array_inst = build_create_array [int_12] builder in
    let begin_with = build_begin_with_op arr_temp builder in
    let float, load_float = build_load_float 0.0 builder in
    let _, sub_inst = build_binary_op int_10 int_13 Minus builder in
    let end_with = build_end_with_op builder in
    let res = [load_int_10; load_int_13; load_int_12; create_array_inst; begin_with; load_float; sub_inst; end_with] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "with" correct prog 