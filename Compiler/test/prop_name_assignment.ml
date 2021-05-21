open Program_types
open Compiler.ProgramBuilder

let input = 
"const v0 = \"function\";
const v1 = 13.37;
const v2 = v0.__proto__;
v2.toString = v1;"

let correct = 
    let builder = init_builder false false false in
    let func_string, load_func_string = build_load_string "function" builder in
    let float, load_float = build_load_float 13.37 builder in
    let prop_temp, load_prop = build_load_prop func_string "__proto__" builder in
    let store_prop = build_store_prop prop_temp float "toString" builder in
    let res = [load_func_string; load_float; load_prop; store_prop] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "prop_name_assignment" correct prog 