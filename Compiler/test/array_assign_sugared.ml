open Program_types
open Compiler.ProgramBuilder

let input = 
"const v0 = 12;
const v1 = [v0,v0,v0];
const v2 = 10;
v1[v2 + 20] += 30;"

let correct = 
    let test_context = init_tracker false false false in
    let int12_temp, load_int_12 = build_load_integer 12L test_context in
    let array_temp, load_array = build_create_array [int12_temp; int12_temp; int12_temp] test_context in
    let int10_temp, load_int_10 = build_load_integer 10L test_context in
    let int20_temp, load_int_20 = build_load_integer 20L test_context in
    let add_res_temp, add_inst = build_binary_op int10_temp int20_temp Plus test_context in
    let int30_temp, load_int_30 = build_load_integer 30L test_context in
    let comp_prop_temp, load_comp_prop_inst = build_load_computed_prop array_temp add_res_temp test_context in
    let add_res_temp2, add_inst2 = build_binary_op comp_prop_temp int30_temp Plus test_context in
    let store_comp_inst = build_store_computed_prop array_temp add_res_temp add_res_temp2 test_context in
    let res = [load_int_12; load_array; load_int_10; load_int_20; add_inst; load_int_30; load_comp_prop_inst; add_inst2; store_comp_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "array_assign_sugared" correct prog 