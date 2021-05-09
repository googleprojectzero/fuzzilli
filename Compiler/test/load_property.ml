open Program_types
open Compiler.ProgramBuilder

let input = 
"const v0 = {};
const v1 = 13.37;
const v2 = v0.__proto__;"
let correct = 
    let builder = init_builder false false false in
    let obj_temp, create_obj = build_create_object [] [] builder in
    let float_temp, load_float_inst = build_load_float 13.37 builder in
    let _, load_prop_inst = build_load_prop obj_temp "__proto__" builder in
    let res = [create_obj; load_float_inst; load_prop_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "load_property" correct prog 