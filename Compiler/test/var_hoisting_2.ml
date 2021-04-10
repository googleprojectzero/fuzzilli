open Program_types
open Compiler.ProgramBuilder

let input = 
"function foo() {
	for(var i = 1; i < 2; i++){
		var asdf = i;
	}
	print(asdf);
}
foo();
"

let correct =
    let test_tracker = init_tracker false false false in
    let func_temp, begin_func_inst, end_func_inst = build_func_ops None [] None false false false test_tracker in
    let undef_temp, load_undef_inst = build_load_undefined test_tracker in
    let integer_temp, load_integer_inst = build_load_integer 1L test_tracker in
    let compare_temp_target, load_compare_temp_inst = build_load_integer 2L test_tracker in
    let compare_temp, compare_inst = build_compare_op integer_temp compare_temp_target LessThan test_tracker in
    let i_temp, load_i_inital_inst = build_load_integer 0L test_tracker in
    let begin_while_inst = build_begin_while compare_temp i_temp NotEqual test_tracker in
    let reassign_hoisted_inst = build_reassign_op undef_temp integer_temp test_tracker in
    let _, inc_loop_var_inst = build_unary_op integer_temp PostInc test_tracker in
    let loop_compare_temp, load_loop_temp_inst = build_load_integer 2L test_tracker in
    let recompare_temp, recompare_inst = build_compare_op integer_temp loop_compare_temp LessThan test_tracker in
    let reassign_loop_compare = build_reassign_op compare_temp recompare_temp test_tracker in
    let end_while__inst = build_end_while test_tracker in
    let print_temp, load_print_inst = build_load_builtin "print" test_tracker in
    let _, call_print_inst = build_call print_temp [undef_temp] test_tracker in
    let _, call_foo_inst = build_call func_temp [] test_tracker in
    let res = [begin_func_inst; load_undef_inst; load_integer_inst; load_compare_temp_inst; compare_inst; load_i_inital_inst; 
        begin_while_inst; reassign_hoisted_inst; inc_loop_var_inst; load_loop_temp_inst; recompare_inst; reassign_loop_compare; end_while__inst;
        load_print_inst; call_print_inst; end_func_inst; call_foo_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "var_hoisting_2" correct prog
    