open Program_types
open Compiler.ProgramBuilder

let input = 
"let i = \"ABC\"
for (i in [0]) {
}
let b = i + \"D\";"

(* Note: Fuzzilli does not support using an existing var  *)
let correct =
    let builder = init_builder false false false in
    let string_temp, load_string_inst = build_load_string "ABC" builder in
    let int_temp, load_int_inst = build_load_integer 0L builder in
    let arr_temp, load_array_inst = build_create_array [int_temp] builder in
    let left_for_in = get_new_intermed_temp builder in
    let _, begin_for_in_inst = build_begin_for_in_op left_for_in arr_temp builder in
    let reassign_inst = build_reassign_op string_temp left_for_in builder in
    let end_for_in_inst = build_end_for_in_op builder in
    let string_temp2, load_string_inst2 = build_load_string "D" builder in
    let add_temp, add_inst = build_binary_op string_temp string_temp2 Plus builder in
    let res = [load_string_inst; load_int_inst; load_array_inst; begin_for_in_inst; reassign_inst; end_for_in_inst; load_string_inst2; add_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "for_in_scoping" correct prog
    