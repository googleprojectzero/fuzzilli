open Program_types

let input = 
"const v1 = 1 * 2 + 2 / 3;
const v2 = 5 * 6 - 2;
const v3 = 9 ** 10;
const v4 = 11 << 12;
const v5 = 13 >> 14;
const v6 = 15 % 16;
const v7 = 17 >>> 2;
"

let correct = [
    {
        inouts = [0l];
        operation = Load_integer {value = 1L};
    };
    {
        inouts = [1l];
        operation = Load_integer {value = 2L};
    };
    {
        inouts = [0l; 1l; 2l];
        operation = Binary_operation {op = Mul};
    };
    {
        inouts = [3l];
        operation = Load_integer {value = 2L};
    };
    {
        inouts = [4l];
        operation = Load_integer {value = 3L};
    };
    {
        inouts = [3l; 4l; 5l];
        operation = Binary_operation {op = Div};
    };
    {
        inouts = [2l; 5l; 6l];
        operation = Binary_operation {op = Add};
    };
    {
        inouts = [7l];
        operation = Load_integer {value = 5L};
    };
    {
        inouts = [8l];
        operation = Load_integer {value = 6L};
    };
    {
        inouts = [7l; 8l; 9l];
        operation = Binary_operation {op = Mul};
    };
    {
        inouts = [10l];
        operation = Load_integer {value = 2L};
    };
    {
        inouts = [9l; 10l; 11l];
        operation = Binary_operation {op = Sub};
    };
    {
        inouts = [12l];
        operation = Load_integer {value = 9L};
    };
    {
        inouts = [13l];
        operation = Load_integer {value = 10L};
    };
    {
        inouts = [12l; 13l; 14l];
        operation = Binary_operation {op = Exp};
    };
    {
        inouts = [15l];
        operation = Load_integer {value = 11L};
    };
    {
        inouts = [16l];
        operation = Load_integer {value = 12L};
    };
    {
        inouts = [15l; 16l; 17l];
        operation = Binary_operation {op = Lshift};
    };
    {
        inouts = [18l];
        operation = Load_integer {value = 13L};
    };
    {
        inouts = [19l];
        operation = Load_integer {value = 14L};
    };
    {
        inouts = [18l; 19l; 20l];
        operation = Binary_operation {op = Rshift};
    };
    {
        inouts = [21l];
        operation = Load_integer {value = 15L};
    };
    {
        inouts = [22l];
        operation = Load_integer {value = 16L};
    };
    {
        inouts = [21l; 22l; 23l];
        operation = Binary_operation {op = Mod};
    };
    {
        inouts = [24l];
        operation = Load_integer {value = 17L};
    };
    {
        inouts = [25l];
        operation = Load_integer {value = 2L};
    };
    {
        inouts = [24l; 25l; 26l];
        operation = Binary_operation {op = Unrshift};
    };
]
    

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false in
    Alcotest.(check (list Util.inst_testable)) "binary_ops" correct prog 