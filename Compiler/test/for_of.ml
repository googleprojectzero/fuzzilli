open Program_types
open Compiler.ProgramBuilder

let input = 
"const v0 = 20;
const v1 = [v0,v0,v0,v0,v0];
for (const v2 of v1){
    isNaN(v2);
}"

let correct = 
    let builder = init_builder false false false in
    let int_20, load_int_20 = build_load_integer 20L builder in
    let array_temp, create_array_inst = build_create_array [int_20; int_20; int_20; int_20; int_20] builder in
    let begin_for_of_temp, begin_for_of_inst = build_begin_for_of_op array_temp builder in
    let isNan_temp, load_IsNaN = build_load_builtin "isNaN" builder in
    let _, call_inst = build_call isNan_temp [begin_for_of_temp] builder in
    let end_for_of = build_end_for_of_op builder in
    let res = [load_int_20; create_array_inst; begin_for_of_inst; load_IsNaN; call_inst; end_for_of] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "for_of" correct prog
    