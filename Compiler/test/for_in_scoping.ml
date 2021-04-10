open Program_types
open Compiler.ProgramBuilder

let input = 
"i = \"ABC\"
for (i in [0]) {
}
b = i + \"D\";"

(* TODO: Figure out why this has a dup and unnecessary var hoisting *)
let correct =
    let tracker = init_tracker false false false in
    let undef_temp, load_undef_inst = build_load_undefined tracker in
    let string_temp, load_string_inst = build_load_string "ABC" tracker in
    let reassign_inst = build_reassign_op undef_temp string_temp tracker in
    let int_temp, load_int_inst = build_load_integer 0L tracker in
    let arr_temp, load_array_inst = build_create_array [int_temp] tracker in
    let _, begin_for_in_inst = build_begin_for_in_op arr_temp tracker in
    let end_for_in_inst = build_end_for_in_op tracker in
    let string_temp2, load_string_inst2 = build_load_string "D" tracker in
    let add_temp, add_inst = build_binary_op undef_temp string_temp2 Plus tracker in
    let _, dup_inst = build_dup_op add_temp tracker in
    let res = [load_undef_inst; load_string_inst; reassign_inst; load_int_inst; load_array_inst; begin_for_in_inst; end_for_in_inst; load_string_inst2; add_inst; dup_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "for_in_scoping" correct prog
    