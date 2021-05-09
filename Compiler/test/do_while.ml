open Program_types
open Compiler.ProgramBuilder

let input = 
"let v0 = 0;
do{
    v0 = v0 + 1;
}while(v0 < 10);
"

let correct = 
    let builder = init_builder false false false in

    let int_0, load_int_0 = build_load_integer 0L builder in
    let int_0_1, load_int_0_1 = build_load_integer 0L builder in
    let dup_var, dup_inst = build_dup_op int_0_1 builder in
    let do_while_inst = build_begin_do_while dup_var int_0_1 NotEqual builder in
    let int_1, load_int_1 = build_load_integer 1L builder in
    let add_temp, add_inst = build_binary_op int_0 int_1 Plus builder in
    let reassign_inst = build_reassign_op int_0 add_temp builder in
    let int_10, load_int_10 = build_load_integer 10L builder in
    let compare_temp, compare_inst = build_compare_op int_0 int_10 LessThan builder in
    let reassign_inst_2 = build_reassign_op dup_var compare_temp builder in
    let end_do_while_inst = build_end_do_while builder in
    let res = [load_int_0; load_int_0_1; dup_inst; do_while_inst; load_int_1; add_inst; reassign_inst; load_int_10;
                compare_inst; reassign_inst_2; end_do_while_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "do_while" correct prog 