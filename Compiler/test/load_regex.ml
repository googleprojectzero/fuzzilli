open Program_types
open Compiler.ProgramBuilder

(* Note: this produces compiler warnings, but seems to work fine *)
let input = 
"const v0 = /\w+\s/i;
const v1 = /\w+\s/g;
const v2 = /\w+\s/m;
const v3 = /\w+\s/s;
const v4 = /\w+\s/u;
const v5 = /\w+\s/y;"

let correct = 
    let builder = init_builder false false false in
    let _, regexp1 = build_load_regex "\\w+\\s" "i" builder in
    let _, regexp2 = build_load_regex "\\w+\\s" "g" builder in
    let _, regexp3 = build_load_regex "\\w+\\s" "m" builder in
    let _, regexp4 = build_load_regex "\\w+\\s" "s" builder in
    let _, regexp5 = build_load_regex "\\w+\\s" "u" builder in
    let _, regexp6 = build_load_regex "\\w+\\s" "y" builder in
    let res = [regexp1; regexp2; regexp3; regexp4; regexp5; regexp6] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "load_regex" correct prog 