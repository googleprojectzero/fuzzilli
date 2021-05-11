open Program_types
open Compiler.ProgramBuilder


let input = 
"function test(a) {
  a[0] = 1.5;
}
a = new Array();"

let correct = 
    let builder = init_builder false false false in
    let func_temp = get_new_intermed_temp builder in
    let _, begin_func_inst, end_func_inst = build_func_ops func_temp ["a"] None false false false builder in
    (* TODO: This needs to be updated along with the function builder interface *)
    let a_temp = match lookup_var_name builder "a" with
        InScope x -> x
        | NotFound -> raise (Invalid_argument "improper variable lookup") in
    
    let int_0, load_int_0 = build_load_integer 0L builder in
    let float_15, load_float = build_load_float 1.5 builder in
    let store_inst = build_store_computed_prop a_temp int_0 float_15 builder in
    let array_builtin, load_builtin_inst = build_load_builtin "Array" builder in
    let construct_temp, construct_inst = build_new_object array_builtin [] builder in
    let _, dup_op = build_dup_op construct_temp builder in
    let res = [begin_func_inst; load_int_0; load_float; store_inst; end_func_inst; load_builtin_inst; construct_inst; dup_op] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "func_param_scoping" correct prog 