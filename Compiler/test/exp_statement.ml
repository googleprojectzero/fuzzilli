open Program_types

let input = 
"let v0 = 0;
const v1 = 5;
v0 = v1 + 1; 
"

let correct = [
    {
        inouts = [0l];
        operation = Load_integer {value = 0L};
    };
    {
        inouts = [1l];
        operation = Load_integer {value = 5L};
    };
    {
        inouts = [2l];
        operation = Load_integer {value = 1L};
    };
    {
        inouts = [1l; 2l; 3l];
        operation = Binary_operation {op = Add};
    };
    {
        inouts = [0l; 3l];
        operation = Reassign;
    };
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false in
    Alcotest.(check (list Util.inst_testable)) "exp_statement" correct prog
    