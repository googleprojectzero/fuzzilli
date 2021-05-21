open Program_types
open Compiler.ProgramBuilder

let input = 
"let v0 = 1;
const v1 = 2
const v7 = {toString:1+2,e:v0+v1};
const v11 = {foobar:3+4,...v7};"

let correct = 
    let builder = init_builder false false false in
    let int_1, load_int_1 = build_load_integer 1L builder in
    let int_2, load_int_2 = build_load_integer 2L builder in
    let int_1_2, load_int_1_2 = build_load_integer 1L builder in
    let int_2_2, load_int_2_2 = build_load_integer 2L builder in
    let second_temp, second_add = build_binary_op int_1_2 int_2_2 Plus builder in
    let first_temp, first_add = build_binary_op int_1 int_2 Plus builder in
    let obj, create_obj_inst = build_create_object ["toString"; "e"] [second_temp; first_temp] builder in

    let int_3, load_int_3 = build_load_integer 3L builder in
    let int_4, load_int_4 = build_load_integer 4L builder in
    let third_temp, third_add = build_binary_op int_3 int_4 Plus builder in
    let _, spread_inst = build_create_object_with_spread ["foobar"] [third_temp; obj] builder in
    let res = [load_int_1; load_int_2; load_int_1_2; load_int_2_2; second_add; first_add; create_obj_inst; load_int_3; load_int_4; third_add; spread_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "spread_object" correct prog 