open Program_types
open Compiler.ProgramBuilder

let input = 
"let v0 = 0;
const v1 = 20;
while(v0 <= v1){
    v0 += 1;
}"

let correct = 
    let builder = init_builder false false false in
    let int_0, load_int_0 = build_load_integer 0L builder in
    let int_20, load_int_20 = build_load_integer 20L builder in
    let compare_temp, compare_inst_0 = build_compare_op int_0 int_20 LessThanEqual builder in
    let int_0_2, load_int_0_2 = build_load_integer 0L builder in
    let begin_while = build_begin_while compare_temp int_0_2 NotEqual builder in
    let int_1, load_int_1 = build_load_integer 1L builder in
    let bin_temp, bin_op = build_binary_op int_0 int_1 Plus builder in
    let reassign_op = build_reassign_op int_0 bin_temp builder in
    let compare_temp2, compare_inst2 = build_compare_op int_0 int_20 LessThanEqual builder in
    let reassign_op2 = build_reassign_op compare_temp compare_temp2 builder in
    let end_while = build_end_while builder in
    let res = [load_int_0; load_int_20; compare_inst_0; load_int_0_2; begin_while; load_int_1; bin_op; reassign_op; compare_inst2; reassign_op2; end_while] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "basic_while" correct prog 