open Program_types
open Compiler.ProgramBuilder

let input = 
"function v1(v2,v3) {
    let v4 = v2 * v3;
    return v4;
}
"

let correct = 
    let builder = init_builder false false false in
    let func_temp = get_new_intermed_temp builder in
    let _, begin_func_inst, end_func_inst = build_func_ops func_temp ["v2"; "v3"] None false false false builder in
    (* TODO: This needs to be updated along with the function builder interface *)
    let v2_temp = match lookup_var_name builder "v2" with
        InScope x -> x
        | NotFound -> raise (Invalid_argument "improper variable lookup") in
    let v3_temp = match lookup_var_name builder "v3" with
        InScope x -> x
        | NotFound -> raise (Invalid_argument "improper variable lookup") in
    let bin_temp, bin_inst = build_binary_op v2_temp v3_temp Mult builder in
    let ret_inst = build_return_op bin_temp builder in
    let res = [begin_func_inst; bin_inst; ret_inst; end_func_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "basic_func_ret" correct prog 