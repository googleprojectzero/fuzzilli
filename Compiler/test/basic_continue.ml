open Program_types
open Compiler.ProgramBuilder

let input = 
"while(1){
    continue;
}
"

let correct = 
    let builder = init_builder false false false in
    let int_temp_1, load_int1 = build_load_integer 1L builder in
    let int_temp_0, load_int0 = build_load_integer 0L builder in
    let begin_while = build_begin_while int_temp_1 int_temp_0 NotEqual builder in
    let continue_inst = build_continue builder in
    let int_temp_1_2, load_int2 = build_load_integer 1L builder in
    let reassign_inst = build_reassign_op int_temp_1 int_temp_1_2 builder in
    let end_while = build_end_while builder in
    let res = [load_int1; load_int0; begin_while; continue_inst; load_int2; reassign_inst; end_while] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "basic_continue" correct prog 