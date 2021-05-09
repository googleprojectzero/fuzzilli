open Program_types
open Compiler.ProgramBuilder

let input = 
"const v1 = new Uint8Array();
const v5 = new Float32Array(12);"

let correct = 
    let builder = init_builder false false false in
    let uint8Array, load_uint8_builtin = build_load_builtin "Uint8Array" builder in
    let _, construct_uin8_inst = build_new_object uint8Array [] builder in
    let float32Array, load_float32_builtin = build_load_builtin "Float32Array" builder in
    let int_12_temp, load_12 = build_load_integer 12L builder in
    let _, construct_float32_inst = build_new_object float32Array [int_12_temp] builder in
    let res = [load_uint8_builtin; construct_uin8_inst; load_float32_builtin; load_12; construct_float32_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "new_test" correct prog 