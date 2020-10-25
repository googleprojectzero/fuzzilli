open Program_types

let input = 
"const v0 = 1 | 2;
const v1 = 3 & 4;
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
        operation = Binary_operation {op = Bit_or};
    };
    {
        inouts = [3l];
        operation = Load_integer {value = 3L};
    };
    {
        inouts = [4l];
        operation = Load_integer {value = 4L};
    };
    {
        inouts = [3l; 4l; 5l];
        operation = Binary_operation {op = Bit_and};
    };
]
    

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false in
    Alcotest.(check (list Util.inst_testable)) "bitwise_ops" correct prog 