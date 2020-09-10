open Program_types

let input = 
"const v0 = 2147483647;
const v1 = \"function\";
try {
    const v2 = v1.repeat(v0);
} catch(v3) {
}"

let correct = [
    {
        inouts = [0l];
        operation = Load_integer {value = 2147483647L};
    };
    {
        inouts = [1l];
        operation = Load_string {value = "function"};
    };
    {
        inouts = [];
        operation = Begin_try;
    };
    {
        inouts = [1l; 0l; 2l];
        operation = Call_method {method_name = "repeat"}
    };
    {
        inouts = [3l];
        operation = Begin_catch;
    };
    {
        inouts = [];
        operation = End_try_catch;
    }
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false in
    Alcotest.(check (list Util.inst_testable)) "prog_1007" correct prog 