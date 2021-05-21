open Program_types
open Compiler.ProgramBuilder

let input = 
"const v0 = 12;
if(v0){
    let v1 = 12;
}"

let correct = 
    let builder = init_builder false false false in
    let temp_12, load_int_12 = build_load_integer 12L builder in
    let begin_if_inst = build_begin_if temp_12 builder in
    let _, load_int_12_2 = build_load_integer 12L builder in
    let begin_else = build_begin_else builder in
    let end_if = build_end_if builder in
    let res = [load_int_12; begin_if_inst; load_int_12_2; begin_else; end_if] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "lone_if" correct prog 