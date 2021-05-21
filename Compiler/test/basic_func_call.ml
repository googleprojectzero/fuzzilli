open Program_types
open Compiler.ProgramBuilder

let input = 
"const v0 = isNaN(0);"

let correct = 
    let builder = init_builder false false false in
    let builtin_temp, load_builtin = build_load_builtin "isNaN" builder in
    let temp_0, load_int = build_load_integer 0L builder in
    let _, call_inst = build_call builtin_temp [temp_0] builder in
    let res = [load_builtin; load_int; call_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "basic_func_call" correct prog 