open Program_types
open Compiler.ProgramBuilder

let input = 
"function foo() {
	for(var i = 1; i < 2; i++){
		var asdf = i;
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
    let compare_temp_target, load_compare_temp_inst = build_load_integer 2L builder in
    let compare_temp, compare_inst = build_compare_op integer_temp compare_temp_target LessThan builder in
    let i_temp, load_i_inital_inst = build_load_integer 0L builder in
    let begin_while_inst = build_begin_while compare_temp i_temp NotEqual builder in
    let reassign_hoisted_inst = build_reassign_op undef_temp integer_temp builder in
    let _, inc_loop_var_inst = build_unary_op integer_temp PostInc builder in
    let loop_compare_temp, load_loop_temp_inst = build_load_integer 2L builder in
    let recompare_temp, recompare_inst = build_compare_op integer_temp loop_compare_temp LessThan builder in
    let reassign_loop_compare = build_reassign_op compare_temp recompare_temp builder in
    let end_while__inst = build_end_while builder in
    let print_temp, load_print_inst = build_load_builtin "isNaN" builder in
    let _, call_print_inst = build_call print_temp [undef_temp] builder in
    let _, call_foo_inst = build_call func_temp [] builder in
    let res = [begin_func_inst; load_undef_inst; load_integer_inst; load_compare_temp_inst; compare_inst; load_i_inital_inst; 
        begin_while_inst; reassign_hoisted_inst; inc_loop_var_inst; load_loop_temp_inst; recompare_inst; reassign_loop_compare; end_while__inst;
        load_print_inst; call_print_inst; end_func_inst; call_foo_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "var_hoisting_2" correct prog
    