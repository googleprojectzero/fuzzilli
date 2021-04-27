open Program_types
open Compiler.ProgramBuilder

let input = 
"for(x in [0]){}
if(1){
	var x = 12;
}
isNaN(x);
"

let correct =
    let builder = init_builder false false false in
    let undef_temp, load_undef_inst = build_load_undefined builder in
    let integer_temp, load_integer_inst = build_load_integer 0L builder in
    let array_temp, array_build_inst = build_create_array [integer_temp] builder in
    let for_in_temp = get_new_intermed_temp builder in
    let _, begin_for_in_inst = build_begin_for_in_op for_in_temp array_temp builder in
    let reassign_inst = build_reassign_op undef_temp for_in_temp builder in
    let end_for_in_inst = build_end_for_in_op builder in
    let if_condition_temp, load_if_condition_inst = build_load_integer 1L builder in
    let begin_if_inst = build_begin_if if_condition_temp builder in
    let load_hoisted_temp, load_hoisted_inst = build_load_integer 12L builder in
    let reassign_inst2 = build_reassign_op undef_temp load_hoisted_temp builder in
    let begin_else_inst = build_begin_else builder in
    let end_if_inst = build_end_if builder in
    let print_temp, load_print_inst = build_load_builtin "isNaN" builder in
    let _, call_print_inst = build_call print_temp [undef_temp] builder in
    let res = [load_undef_inst; load_integer_inst; array_build_inst; begin_for_in_inst; reassign_inst; end_for_in_inst; load_if_condition_inst; begin_if_inst; load_hoisted_inst; reassign_inst2; begin_else_inst; end_if_inst; load_print_inst; call_print_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "var_hoisting_shadow" correct prog
    