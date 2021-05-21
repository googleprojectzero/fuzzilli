open Program_types
open Compiler.ProgramBuilder

let input = 
"const v0 = true;
const v1 = false;"

let correct = 
    let builder = init_builder false false false in
    let _, load_true = build_load_bool true builder in
    let _, load_false = build_load_bool false builder in
    let res = [load_true; load_false] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "load_bool" correct prog 