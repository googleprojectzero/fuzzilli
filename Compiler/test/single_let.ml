open Program_types
open Compiler.ProgramBuilder

let input = 
"let v0 = 0;
v0 = 12;"

let correct = 
    let builder = init_builder false false false in
    let int_0_temp, load_0_inst = build_load_integer 0L builder in
    let int_12_temp, load_12_inst = build_load_integer 12L builder in
    let reassign_inst = build_reassign_op int_0_temp int_12_temp builder in
    let res = [load_0_inst; load_12_inst; reassign_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "single_let" correct prog 