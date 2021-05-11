open Program_types
open Compiler.ProgramBuilder

let input = 
"let v0 = 1;
const v1 = 2
const v7 = {toString:1+2,e:v0+v1};"

let correct = 
    let builder = init_builder false false false in
    let int_1, load_int_1 = build_load_integer 1L builder in
    let int_2, load_int_2 = build_load_integer 2L builder in
    let int_1_2, load_int_1_2 = build_load_integer 1L builder in
    let int_2_2, load_int_2_2 = build_load_integer 2L builder in
    let second_temp, second_add = build_binary_op int_1_2 int_2_2 Plus builder in
    let first_temp, first_add = build_binary_op int_1 int_2 Plus builder in
    let _, create_obj_inst = build_create_object ["toString"; "e"] [second_temp; first_temp] builder in
    let res = [load_int_1; load_int_2; load_int_1_2; load_int_2_2; second_add; first_add; create_obj_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "object_creation" correct prog 