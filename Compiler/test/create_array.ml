open Program_types
open Compiler.ProgramBuilder

let input = 
"const v0 = 15;
const v1 = 20;
const v2 = [v1,v0];
"

let correct = 
    let builder = init_builder false false false in
    let int_15_temp, load_int_15 = build_load_integer 15L builder in
    let int_20_temp, load_int_20 = build_load_integer 20L builder in
    let _, create_array = build_create_array [int_20_temp; int_15_temp] builder in
    let res = [load_int_15; load_int_20; create_array] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "create_array" correct prog 