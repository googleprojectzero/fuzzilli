open Program_types
open Compiler.ProgramBuilder

let input = 
"const v0 = function () { const v1 = 12; return v1;}
%PrepareFunctionForOptimization(v0);"

let correct = 
    let builder = init_builder false true true in
    let func_temp = get_new_intermed_temp builder in
    let _, begin_func_inst, end_func_inst = build_func_ops func_temp [] None false false false builder in
    let int_12, load_12 = build_load_integer 12L builder in
    let ret_inst = build_return_op int_12 builder in
    let builtin_temp, load_builtin = build_load_builtin "PrepareFunctionForOptimization" builder in
    let _, call_inst = build_call builtin_temp [func_temp] builder in
    let res = [begin_func_inst; load_12; ret_inst; end_func_inst; load_builtin; call_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false true true in
    Alcotest.(check (list Util.inst_testable)) "v8_natives" correct prog 