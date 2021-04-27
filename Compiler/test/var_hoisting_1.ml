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
    let builder = init_builder false false false in
    let func_temp = get_new_intermed_temp builder in
    let _, begin_func_inst, end_func_inst = build_func_ops func_temp [] None false false false builder in
    let undef_temp, load_undef_inst = build_load_undefined builder in
    let integer_temp, load_integer_inst = build_load_integer 1L builder in
    let begin_if_inst = build_begin_if integer_temp builder in
    let load_hoisted_temp, load_hoisted_inst = build_load_integer 12L builder in
    let reassign_inst = build_reassign_op undef_temp load_hoisted_temp builder in
    let begin_else_inst = build_begin_else builder in
    let end_if_inst = build_end_if builder in
    let print_temp, load_print_inst = build_load_builtin "isNaN" builder in
    let _, call_print_inst = build_call print_temp [undef_temp] builder in
    let _, call_foo_inst = build_call func_temp [] builder in
    let res = [begin_func_inst; load_undef_inst; load_integer_inst; begin_if_inst; load_hoisted_inst; reassign_inst; begin_else_inst; end_if_inst; load_print_inst; call_print_inst; end_func_inst; call_foo_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "var_hoisting_1" correct prog
    