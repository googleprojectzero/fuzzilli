open Program_types

let input = 
"var a = void (1 + 2);"

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
        operation = Binary_operation {op = Add};
    };
    {
        inouts = [3l];
        operation = Load_undefined;
    };
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false in
    Alcotest.(check (list Util.inst_testable)) "void" correct prog 