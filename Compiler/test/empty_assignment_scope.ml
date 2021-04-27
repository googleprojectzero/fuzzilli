open Program_types
open Compiler.ProgramBuilder

let input = 
"
var x;
while (x != 0) {
    x = 1;
}
"

let correct = 
    let builder = init_builder false false false in
    let undef_temp, undef_inst = build_load_undefined builder in
    let dup_temp, dup_inst = build_dup_op undef_temp builder in
    let compare_target_temp, build_compare_target = build_load_integer 0L builder in
    let compare_res_temp, build_compare = build_compare_op dup_temp compare_target_temp NotEqual builder in
    let zero_temp, load_zero_temp = build_load_integer 0L builder in
    let begin_while_inst = build_begin_while compare_res_temp zero_temp NotEqual builder in
    let one_temp, load_one_temp = build_load_integer 1L builder in
    let reassign_inst = build_reassign_op dup_temp one_temp builder in
    let second_compare_target_temp, build_second_compare_target_inst = build_load_integer 0L builder in
    let second_compare_temp, build_second_compare_inst = build_compare_op dup_temp second_compare_target_temp NotEqual builder in
    let second_reassign_inst = build_reassign_op compare_res_temp second_compare_temp builder in
    let end_while_inst = build_end_while builder in
    let res = [undef_inst; dup_inst; build_compare_target; build_compare; load_zero_temp; begin_while_inst; load_one_temp; reassign_inst;
        build_second_compare_target_inst; build_second_compare_inst; second_reassign_inst; end_while_inst ] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "empty_assignment_scope" correct prog
    