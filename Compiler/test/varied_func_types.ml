open Program_types
open Compiler.ProgramBuilder


let input = 
"const v0 = [1,2,3];
const v1 = (v0) => {
    return v0 + 4;
};
async function v2(v0) {
    return v0 + 5;
}
const v3 = async (v0) => {
    return v0 + 5;
}
function * v4(v0) {
    yield v0 + 6;
}
function * v5(v0) {
    yield *v0;
}"

let correct = 
    let builder = init_builder false false false in
    let int_1, load_int_1 = build_load_integer 1L builder in
    let int_2, load_int_2 = build_load_integer 2L builder in
    let int_3, load_int_3 = build_load_integer 3L builder in
    let array_temp, create_array_inst = build_create_array [int_1; int_2; int_3] builder in

    (* TODO: Update this when updating the function op interface *)
    let arrow_func_temp = get_new_intermed_temp builder in
    let _, begin_arrow_inst, end_arrow_inst = build_func_ops arrow_func_temp ["v0"] None true false false builder in
    let v0_temp_1 = match lookup_var_name builder "v0" with
        InScope x -> x
        | NotFound -> raise (Invalid_argument "improper variable lookup") in
    let int_4, load_int_4 = build_load_integer 4L builder in
    let add_temp_1, add_inst_1 = build_binary_op v0_temp_1 int_4 Plus builder in
    let return_1 = build_return_op add_temp_1 builder in

    let async_func_temp = get_new_intermed_temp builder in
    let _, begin_async_inst, end_asnyc_inst = build_func_ops async_func_temp ["v0"] None false true false builder in
    let v0_temp_2 = match lookup_var_name builder "v0" with
        InScope x -> x
        | NotFound -> raise (Invalid_argument "improper variable lookup") in
    let int_5, load_int_5 = build_load_integer 5L builder in
    let add_temp_2, add_inst_2 = build_binary_op v0_temp_2 int_5 Plus builder in
    let return_2 = build_return_op add_temp_2 builder in

    let async_arrow_func_temp = get_new_intermed_temp builder in
    let _, begin_async_arrow_inst, end_asnyc_arrow_inst = build_func_ops async_arrow_func_temp ["v0"] None true true false builder in
    let v0_temp_3 = match lookup_var_name builder "v0" with
        InScope x -> x
        | NotFound -> raise (Invalid_argument "improper variable lookup") in
    let int_5_2, load_int_5_2 = build_load_integer 5L builder in
    let add_temp_3, add_inst_3 = build_binary_op v0_temp_3 int_5_2 Plus builder in
    let return_3 = build_return_op add_temp_3 builder in

    let generator_func_temp_1 = get_new_intermed_temp builder in
    let _, begin_generator_func_1, end_generator_func_1 = build_func_ops generator_func_temp_1 ["v0"] None false false true builder in
    let v0_temp_4 = match lookup_var_name builder "v0" with
        InScope x -> x
        | NotFound -> raise (Invalid_argument "improper variable lookup") in
    let int_6, load_int_6 = build_load_integer 6L builder in
    let add_temp_4, add_inst_4 = build_binary_op v0_temp_4 int_6 Plus builder in
    let yield_inst = build_yield_op add_temp_4 builder in

    let generator_func_temp_2 = get_new_intermed_temp builder in
    let _, begin_generator_func_2, end_generator_func_2 = build_func_ops generator_func_temp_2 ["v0"] None false false true builder in
    let v0_temp_5 = match lookup_var_name builder "v0" with
        InScope x -> x
        | NotFound -> raise (Invalid_argument "improper variable lookup") in
    let yield_each_inst = build_yield_each_op v0_temp_5 builder in

    let res = [load_int_1; load_int_2; load_int_3; create_array_inst;
        begin_arrow_inst; load_int_4; add_inst_1; return_1; end_arrow_inst;
        begin_async_inst; load_int_5; add_inst_2; return_2; end_asnyc_inst;
        begin_async_arrow_inst; load_int_5_2; add_inst_3; return_3; end_asnyc_arrow_inst;
        begin_generator_func_1; load_int_6; add_inst_4; yield_inst; end_generator_func_1;
        begin_generator_func_2; yield_each_inst; end_generator_func_2
        ] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "varied_func_types" correct prog 