open Program_types
open Compiler.ProgramBuilder
let input = 
"const v0 = 1;
while(v0){
    break;
}"

let correct = 
    let builder = init_builder false false false in
    let int_temp, load_int = build_load_integer 1L builder in
    let int_temp0, load_int0 = build_load_integer 0L builder in
    let begin_while_inst = build_begin_while int_temp int_temp0 NotEqual builder in
    let break_inst = build_break_op builder in
    let reassign_inst = build_reassign_op int_temp int_temp builder in
    let end_while_inst = build_end_while builder in
    let res = [load_int; load_int0; begin_while_inst; break_inst; reassign_inst; end_while_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "basic_break" correct prog 