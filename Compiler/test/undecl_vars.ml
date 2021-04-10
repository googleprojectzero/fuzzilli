open Program_types

let input = 
"const v0 = \"00HzDRcP64\";
let length = v0;
let v2 = isNaN(length);"

let correct = [
    {
        inouts = [0l];
        operation = Load_string {value = "00HzDRcP64"};
    };
    {
        inouts = [1l];
        operation = Load_builtin {builtin_name = "isNaN"};
    };
    {
        inouts = [1l; 0l; 2l];
        operation = Call_function;
    }
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "undecl_vars" correct prog 