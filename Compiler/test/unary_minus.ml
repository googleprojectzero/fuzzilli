open Program_types
open Compiler.ProgramBuilder

let input = 
"const v2 = -256;"

let correct = 
    let builder = init_builder false false false in
    let pos_temp, load_int = build_load_integer 256L builder in
    let _, unary_inst = build_unary_op pos_temp Minus builder in
    let res = [load_int; unary_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "unary_minus" correct prog 