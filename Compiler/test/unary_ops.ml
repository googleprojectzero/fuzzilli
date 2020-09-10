open Program_types

let input = 
"const v0 = !true;
const v1 = !false;
const v2 = !v0;
const v3 = ~5;"

let correct = [
    {
        inouts = [0l];
        operation = Load_boolean {value = true};
    };
    {
        inouts = [0l; 1l];
        operation = Unary_operation {op = Logical_not};
    };
    {
        inouts = [2l];
        operation = Load_boolean {value = false};
    };
    {
        inouts = [2l; 3l];
        operation = Unary_operation {op = Logical_not};
    };
    {
        inouts = [1l; 4l];
        operation = Unary_operation {op = Logical_not};
    };
    {
        inouts = [5l];
        operation = Load_integer {value = 5L};
    };
    {
        inouts = [5l; 6l];
        operation = Unary_operation {op = Bitwise_not};
    };
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false in
    Alcotest.(check (list Util.inst_testable)) "unary_ops" correct prog 