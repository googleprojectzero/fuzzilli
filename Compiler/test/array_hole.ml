open Program_types
open Compiler.ProgramBuilder

let input = 
"let a = [1,,1];"

let correct = 
    let builder = init_builder false false false in
    let int_temp, load_int = build_load_integer 1L builder in
    let undef_temp, load_undef_inst = build_load_undefined builder in
    let int_temp2, load_int_2 = build_load_integer 1L builder in
    let _, create_array_inst = build_create_array [int_temp; undef_temp; int_temp2] builder in
    let res = [load_int; load_undef_inst; load_int_2; create_array_inst] in
    List.map inst_to_prog_inst res
let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "array_hole" correct prog 