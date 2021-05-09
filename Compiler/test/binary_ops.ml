open Program_types
open Compiler.ProgramBuilder

let input = 
"const v1 = 1 * 2 + 2 / 3;
const v2 = 5 * 6 - 2;
const v3 = 9 ** 10;
const v4 = 11 << 12;
const v5 = 13 >> 14;
const v6 = 15 % 16;
const v7 = 17 >>> 2;
"

let correct = 
    let builder = init_builder false false false in
    let int_1, load_int_1 = build_load_integer 1L builder in
    let int_2, load_int_2 = build_load_integer 2L builder in
    let mul_temp, mul_op = build_binary_op int_1 int_2 Mult builder in
    let int_2_2, load_int_2_2 = build_load_integer 2L builder in
    let int_3, load_int_3 = build_load_integer 3L builder in
    let dev_temp, div_op = build_binary_op int_2_2 int_3 Div builder in
    let _, add_op = build_binary_op mul_temp dev_temp Plus builder in
    let int_5, load_int_5 = build_load_integer 5L builder in
    let int_6, load_int_6 = build_load_integer 6L builder in
    let mul_temp_2, mul_op_2 = build_binary_op int_5 int_6 Mult builder in
    let int_2_3, load_int_2_3 = build_load_integer 2L builder in
    let _, sub_op = build_binary_op mul_temp_2 int_2_3 Minus builder in
    let int_9, load_int_9 = build_load_integer 9L builder in
    let int_10, load_int_10 = build_load_integer 10L builder in
    let _, exp_op = build_binary_op int_9 int_10 Exp builder in
    let int_11, load_int_11 = build_load_integer 11L builder in
    let int_12, load_int_12 = build_load_integer 12L builder in
    let _, lshift_op = build_binary_op int_11 int_12 LShift builder in
    let int_13, load_int_13 = build_load_integer 13L builder in
    let int_14, load_int_14 = build_load_integer 14L builder in
    let _, right_op = build_binary_op int_13 int_14 RShift builder in
    let int_15, load_int_15 = build_load_integer 15L builder in
    let int_16, load_int_16 = build_load_integer 16L builder in
    let _, mod_op = build_binary_op int_15 int_16 Mod builder in
    let int_17, load_int_17 = build_load_integer 17L builder in
    let int_2_4, load_int_2_4 = build_load_integer 2L builder in
    let _, unshift_op = build_binary_op int_17 int_2_4 RShift3 builder in
    let res = [load_int_1; load_int_2; mul_op; load_int_2_2; load_int_3; div_op; add_op; load_int_5;
                    load_int_6; mul_op_2; load_int_2_3; sub_op; load_int_9; load_int_10; exp_op;
                    load_int_11; load_int_12; lshift_op; load_int_13; load_int_14; right_op;
                    load_int_15; load_int_16; mod_op; load_int_17; load_int_2_4; unshift_op] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "binary_ops" correct prog 