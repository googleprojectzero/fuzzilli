open Program_types
open Compiler.ProgramBuilder

let input = 
"function test(v0, ...v101){
    return v0 + v101[0];
}
const v5 = [0,1];
const v17 = test(10,...v5);
"

let correct = 
    let builder = init_builder false false false in
    let func_temp = get_new_intermed_temp builder in
    let _, begin_func_inst, end_func_inst = build_func_ops func_temp ["v0"] (Some "v101") false false false builder in
    (* TODO: Update this along with the function interface *)
    let v0_temp = match lookup_var_name builder "v0" with
        InScope x -> x
        | NotFound -> raise (Invalid_argument "improper variable lookup") in
    let v101_temp = match lookup_var_name builder "v101" with
        InScope x -> x
        | NotFound -> raise (Invalid_argument "improper variable lookup") in
    let elem_temp, load_elem_inst = build_load_element v101_temp 0 builder in
    let bin_temp, bin_inst = build_binary_op v0_temp elem_temp Plus builder in
    let ret_inst = build_return_op bin_temp builder in

    let int_0, load_int_0 = build_load_integer 0L builder in
    let int_1, load_int_1 = build_load_integer 1L builder in

    let arr_temp, create_arr_temp = build_create_array [int_0; int_1] builder in
    let int_10, load_int_10 = build_load_integer 10L builder in
    let _, call_inst = build_call_with_spread func_temp [int_10; arr_temp] [false; true] builder in
    let res = [begin_func_inst; load_elem_inst; bin_inst; ret_inst; end_func_inst; load_int_0; load_int_1; create_arr_temp; load_int_10; call_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "func_call_with_spread" correct prog 