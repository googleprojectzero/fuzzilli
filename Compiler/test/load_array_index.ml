open Program_types
open Compiler.ProgramBuilder

let input = 
"const v3 = [0,1,2];
const v5 = v3[0];
const v7 = v3[v5];"

let correct = 
    let builder = init_builder false false false in
    let int_0, load_int_0 = build_load_integer 0L builder in
    let int_1, load_int_1 = build_load_integer 1L builder in
    let int_2, load_int_2 = build_load_integer 2L builder in
    let arr_temp, create_arr = build_create_array [int_0; int_1; int_2] builder in
    let elem_temp, load_elem_inst = build_load_element arr_temp 0 builder in
    let _, load_comp_elem_inst = build_load_computed_prop arr_temp elem_temp builder in
    let res = [load_int_0; load_int_1; load_int_2; create_arr; load_elem_inst; load_comp_elem_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "load_array_index" correct prog 