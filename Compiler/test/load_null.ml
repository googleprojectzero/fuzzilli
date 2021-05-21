open Program_types
open Compiler.ProgramBuilder

let input = 
"const v0 = null;"

let correct = 
    let builder = init_builder false false false in
    let _, load_null = build_load_null builder in
    let res = [load_null] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "load_null" correct prog 