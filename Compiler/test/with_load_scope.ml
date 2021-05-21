open Program_types
open Compiler.ProgramBuilder

let input = 
"const v9 = {__proto__:0,length:0};
with (v9) {
    const v11 = length;
}
"

(* TODO: This may not be correct, as length should come from v9 *)
let correct = 
    let builder = init_builder false false false in
    let int_0_1, load_int_0_1 = build_load_integer 0L builder in
    let int_0_2, load_int_0_2 = build_load_integer 0L builder in
    let obj_temp, create_obj = build_create_object ["__proto__"; "length"] [int_0_1; int_0_2] builder in
    let begin_with = build_begin_with_op obj_temp builder in
    let _, load_builtin = build_load_builtin "placeholder" builder in
    let end_with = build_end_with_op builder in
    let res = [load_int_0_1; load_int_0_2; create_obj; begin_with; load_builtin; end_with] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "with" correct prog 