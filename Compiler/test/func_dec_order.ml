open Program_types
open Compiler.ProgramBuilder

let input = 
"function b() {a();}
function a() {
  return 7;
}
"

let correct =
    let builder = init_builder false false false in
    let undef_temp, load_undef_inst = build_load_undefined builder in
    let func_temp = get_new_intermed_temp builder in
    let _, begin_func_inst, end_func_inst = build_func_ops func_temp [] None false false false builder in
    let _, call_inst = build_call undef_temp [] builder in
    let func_temp2 = get_new_intermed_temp builder in
    let _, begin_func_inst_2, end_func_inst_2 = build_func_ops func_temp2 [] None false false false builder in
    let int_temp, load_int_inst = build_load_integer 7L builder in
    let ret_inst = build_return_op int_temp builder in
    let reassign_inst = build_reassign_op undef_temp func_temp2 builder in
    let res = [load_undef_inst; begin_func_inst; call_inst; end_func_inst; begin_func_inst_2; load_int_inst; ret_inst; end_func_inst_2; reassign_inst ] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "func_dec_order" correct prog 