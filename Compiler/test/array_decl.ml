open Program_types
open Compiler.ProgramBuilder

let input = 
"var [r, g, f] = [20, 15, 35];
"

let correct = 
    let builder = init_builder false false false in
    let _, l0_inst = build_load_integer 20L builder in
    let _, l1_inst = build_load_integer 15L builder in
    let _, l2_inst = build_load_integer 35L builder in
    let res = [l0_inst; l1_inst; l2_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "array_decl" correct prog
    