open Program_types
open Compiler.ProgramBuilder

let input = 
"const v0 = 0;
const v1 = [v0,...v0,];"

let correct = 
    let builder = init_builder false false false in
    let int_temp, load_int = build_load_integer 0L builder in
    let _, create_array_inst = build_create_array_with_spread [int_temp; int_temp] [false; true] builder in
    let res = [load_int; create_array_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "array_spread" correct prog 