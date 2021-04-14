open Program_types
open Compiler.ProgramBuilder

let input = 
"function foo() {
	if(1){
		var asdf = 12;
	}
	isNaN(asdf);
}
foo();
"

let correct =
    let tracker = init_tracker false false false in
    let func_temp = get_new_intermed_temp tracker in
    let _, begin_func_inst, end_func_inst = build_func_ops func_temp [] None false false false tracker in
    let undef_temp, load_undef_inst = build_load_undefined tracker in
    let integer_temp, load_integer_inst = build_load_integer 1L tracker in
    let begin_if_inst = build_begin_if integer_temp tracker in
    let load_hoisted_temp, load_hoisted_inst = build_load_integer 12L tracker in
    let reassign_inst = build_reassign_op undef_temp load_hoisted_temp tracker in
    let begin_else_inst = build_begin_else tracker in
    let end_if_inst = build_end_if tracker in
    let print_temp, load_print_inst = build_load_builtin "isNaN" tracker in
    let _, call_print_inst = build_call print_temp [undef_temp] tracker in
    let _, call_foo_inst = build_call func_temp [] tracker in
    let res = [begin_func_inst; load_undef_inst; load_integer_inst; begin_if_inst; load_hoisted_inst; reassign_inst; begin_else_inst; end_if_inst; load_print_inst; call_print_inst; end_func_inst; call_foo_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "var_hoisting_1" correct prog
    