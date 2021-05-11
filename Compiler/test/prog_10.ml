open Program_types
open Compiler.ProgramBuilder

let input = 
"const v0 = 4294967296;
const v1 = isNaN;
const v2 = v0 === v1;
const v3 = v0 == v1;
const v4 = 13.37;
const v5 = [v4,v4];
const v6 = 1337;
const v7 = {toString:v5,e:v6};"

let correct = 
    let builder = init_builder false false false in
    let large_int, load_large_int = build_load_integer 4294967296L builder in
    let isNaN, load_isNaN = build_load_builtin "isNaN" builder in
    let _, compare_inst = build_compare_op large_int isNaN StrictEqual builder in
    let _, compare_inst_2 = build_compare_op large_int isNaN Equal builder in
    let float, load_float = build_load_float 13.37 builder in
    let array, create_array = build_create_array [float; float] builder in
    let int_1337, load_int_1337 = build_load_integer 1337L builder in
    let _, create_object = build_create_object ["toString"; "e"] [array; int_1337] builder in
    let res = [load_large_int; load_isNaN; compare_inst; compare_inst_2; load_float; create_array; load_int_1337; create_object] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "prog_10" correct prog 