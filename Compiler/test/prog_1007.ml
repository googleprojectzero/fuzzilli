open Program_types
open Compiler.ProgramBuilder

let input = 
"const v0 = 2147483647;
const v1 = \"function\";
try {
    const v2 = v1.repeat(v0);
} catch(v3) {
}"

let correct = 
    let builder = init_builder false false false in
    let large_int, load_large_int = build_load_integer 2147483647L builder in
    let func_string, load_func_string = build_load_string "function" builder in
    let begin_try = build_begin_try_op builder in
    let _, call_method = build_call_method func_string [large_int] "repeat" builder in
    let begin_catch = build_begin_catch_op "foobarbaz" builder in
    let end_catch = build_end_try_catch_op builder in
    let res = [load_large_int; load_func_string; begin_try; call_method; begin_catch; end_catch] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "prog_1007" correct prog 