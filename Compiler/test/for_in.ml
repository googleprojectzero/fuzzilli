open Program_types
open Compiler.ProgramBuilder


let input = 
"const v0 = 12;
const v1 = [v0,v0,v0,v0,v0];
for (const v2 in v1) {
    let v3 = v2;
    isNaN(v3);
}"

let correct = 
    let builder = init_builder false false false in
    let int_12, load_int_12 = build_load_integer 12L builder in
    let arr_temp, create_arr_inst = build_create_array [int_12; int_12; int_12; int_12; int_12] builder in
    let left_temp = get_new_intermed_temp builder in
    let _, begin_for_in = build_begin_for_in_op left_temp arr_temp builder in
    let builtin_temp, load_builtin = build_load_builtin "isNaN" builder in
    let _, call_inst = build_call builtin_temp [left_temp] builder in
    let end_for_in = build_end_for_in_op builder in
    let res = [load_int_12; create_arr_inst; begin_for_in; load_builtin; call_inst; end_for_in] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "for_in_scoping" correct prog
    