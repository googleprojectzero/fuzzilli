open Program_types

let input = 
"const v0 = isNaN(0);"

let correct = [
    {
        inouts = [0l];
        operation = Load_builtin {builtin_name = "isNaN"};
    };
    {
        inouts = [1l];
        operation = Load_integer {value = 0L};
    };
    {
        inouts = [0l; 1l; 2l];
        operation = Call_function;
    };
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false in
    Alcotest.(check (list Util.inst_testable)) "basic_func_call" correct prog 