open Program_types
open Compiler.ProgramBuilder

let input = 
"if(1){
    const v0 = 3;
} else if(2){
    const v1 = 4;
} else {
    const v2 = 5;
}
"
let correct = 
    let builder = init_builder false false false in
    let int_1, load_int_1 = build_load_integer 1L builder in
    let begin_if_inst_1 = build_begin_if int_1 builder in
    let int_3, load_int_3 = build_load_integer 3L builder in
    let else_inst = build_begin_else builder in
    let int_2, load_int_2 = build_load_integer 2L builder in
    let begin_if_inst_2 = build_begin_if int_2 builder in
    let int_4, load_int_4 = build_load_integer 4L builder in
    let int_5, load_int_5 = build_load_integer 5L builder in
    let end_if_inst = build_end_if builder in
    let res = [load_int_1; begin_if_inst_1; load_int_3; else_inst; load_int_2; begin_if_inst_2; load_int_4; else_inst;
        load_int_5; end_if_inst; end_if_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "if_else" correct prog
    