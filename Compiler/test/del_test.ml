open Program_types
open Compiler.ProgramBuilder


let input = 
"const v0 = 1337;
const v1 = [v0];
delete v1[0];
const v10 = \"function\";
delete v10.length;
"

let correct = 
    let builder = init_builder false false false in
    let int1337, load_1337 = build_load_integer 1337L builder in
    let arr_temp, build_array = build_create_array [int1337] builder in
    let zero_temp, load_zero_temp = build_load_integer 0L builder in
    let _, del_inst = build_delete_computed_prop arr_temp zero_temp builder in
    let string_temp, load_string_temp = build_load_string "function" builder in
    let _, del_inst2 = build_delete_prop string_temp "length" builder in
    let res = [load_1337; build_array; load_zero_temp; del_inst; load_string_temp; del_inst2] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "del_test" correct prog 