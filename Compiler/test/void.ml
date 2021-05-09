open Program_types
open Compiler.ProgramBuilder

let input = 
"let a = void (1 + 2);"

let correct = 
    let builder = init_builder false false false in
    let int_1, load_int_1 = build_load_integer 1L builder in
    let int_2, load_int_2 = build_load_integer 2L builder in
    let _, binary_op = build_binary_op int_1 int_2 Plus builder in
    let _, load_undef = build_load_undefined builder in
    let res = [load_int_1; load_int_2; binary_op; load_undef] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "void" correct prog 