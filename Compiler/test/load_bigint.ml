open Compiler.ProgramBuilder
open Program_types

let input = 
"const v0 = 9007199254740991n;"

let correct = 
    let builder = init_builder false false false in
    let _, load_big_int_inst = build_load_bigInt 9007199254740991.0 builder in
    let res = [load_big_int_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "load_bigint" correct prog 