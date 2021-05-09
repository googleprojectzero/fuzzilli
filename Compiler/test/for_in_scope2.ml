open Program_types
open Compiler.ProgramBuilder

let input = 
"for (var x in x) {
  function x() {
    ;
  }
  let a = x();
}
"

let correct = 
    let builder = init_builder false false false in
    let placeholder_temp, load_placeholder = build_load_builtin "placeholder" builder in
    let temp = get_new_intermed_temp builder in
    let _, begin_for_in = build_begin_for_in_op temp placeholder_temp builder in
    let func_temp = get_new_intermed_temp builder in
    let func_temp2, begin_func_inst, end_func_inst = build_func_ops func_temp [] None false false false builder in
    let _, call_inst = build_call func_temp2 [] builder in
    let end_for_in = build_end_for_in_op builder in
    let res = [load_placeholder; begin_for_in; begin_func_inst; end_func_inst; call_inst; end_for_in] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "for_in_scope2" correct prog
    