open Program_types

let input = 
"const v0 = 0;
throw v0;"

let correct = [
    {
        inouts = [0l];
        operation = Load_integer {value = 0L};
    };
    {
        inouts = [0l];
        operation = Throw_exception;
    }
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false in
    Alcotest.(check (list Util.inst_testable)) "throw" correct prog 