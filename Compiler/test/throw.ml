open Program_types
open Compiler.ProgramBuilder

let input = 
"const v0 = 0;
throw v0;"

let correct = 
    let builder = init_builder false false false in
    let temp_0, load_0 = build_load_integer 0L builder in
    let inst = build_throw_op temp_0 builder in
    let res = [load_0; inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "throw" correct prog 