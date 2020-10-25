open Program_types

let input = 
"const v0 = \"00HzDRcP64\";
length = v0;
isNaN(length);"

let correct = [
    {
        inouts = [0l];
        operation = Load_string {value = "00HzDRcP64"};
    };
    {
        inouts = [0l; 1l];
        operation = Dup;
    };
    {
        inouts = [2l];
        operation = Load_builtin {builtin_name = "isNaN"};
    };
    {
        inouts = [2l; 1l; 3l];
        operation = Call_function;
    }
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "undecl_vars" correct prog 