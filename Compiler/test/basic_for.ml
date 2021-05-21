open Program_types
open Compiler.ProgramBuilder

let input = 
"for(let v0 = 2; v0 < 10; v0 = v0 + 1){
    let v2 = v0 + 12;
}"

let correct = 
    let builder = init_builder false false false in
    let int_2_temp, load_int2 = build_load_integer 2L builder in
    let int_10_temp, load_int10 = build_load_integer 10L builder in
    let compare_temp, first_compare_inst = build_compare_op int_2_temp int_10_temp LessThan builder in
    let int_0_temp, load_int0 = build_load_integer 0L builder in
    let begin_while = build_begin_while compare_temp int_0_temp NotEqual builder in
    let int_12_temp, load_int12 = build_load_integer 12L builder in
    let add_temp, add_inst = build_binary_op int_2_temp int_12_temp Plus builder in
    let int_1_temp, load_int1 = build_load_integer 1L builder in
    let add_temp2, add_inst2 = build_binary_op int_2_temp int_1_temp Plus builder in
    let reassign_op = build_reassign_op int_2_temp add_temp2 builder in
    let int_10_temp2, load_int102 = build_load_integer 10L builder in
    let compare_temp2, second_compare_inst = build_compare_op int_2_temp int_10_temp2 LessThan builder in
    let reassign_op2 = build_reassign_op compare_temp compare_temp2 builder in
    let end_while = build_end_while builder in
    let res = [load_int2; load_int10; first_compare_inst; load_int0; begin_while; load_int12; add_inst; load_int1; add_inst2; reassign_op; load_int102; second_compare_inst; reassign_op2; end_while] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "basic_for" correct prog
    