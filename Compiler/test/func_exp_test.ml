open Program_types
open Compiler.ProgramBuilder

let input = 
"const v0 = function () { const v1 = 12; return v1;}
const v2 = v0();
"

let correct = 
    let builder = init_builder false false false in
    (* TODO: This needs to be updated along with the function builder interface *)
    let func_temp = get_new_intermed_temp builder in
    let _, begin_func_inst, end_func_inst = build_func_ops func_temp [] None false false false builder in
    let int_12, load_int_12 = build_load_integer 12L builder in
    let return_inst = build_return_op int_12 builder in
    let _, call_inst = build_call func_temp [] builder in
    let res = [begin_func_inst; load_int_12; return_inst; end_func_inst; call_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "func_exp_test" correct prog 