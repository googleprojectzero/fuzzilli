open Program_types
open Compiler.ProgramBuilder

let input = 
"const v0 = {};
const v1 = 13.37;
v0.a = 10;
v0.a += v1;"

let correct = 
    let builder = init_builder false false false in
    let obj, create_obj = build_create_object [] [] builder in
    let float, load_float = build_load_float 13.37 builder in
    let int, load_int = build_load_integer 10L builder in
    let store_prop = build_store_prop obj int "a" builder in
    let temp_prop, load_prop = build_load_prop obj "a" builder in
    let add_temp, add_inst = build_binary_op temp_prop float Plus builder in
    let store_prop2 = build_store_prop obj add_temp "a" builder in
    let res = [create_obj; load_float; load_int; store_prop; load_prop; add_inst; store_prop2] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "store_property_sugared" correct prog 