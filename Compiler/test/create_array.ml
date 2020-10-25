open Program_types

let input = 
"const v0 = 15;
const v1 = 20;
const v2 = [v1,v0];
"

let correct = [
    {
        inouts = [0l];
        operation = Load_integer {value = 15L};
    };
    {
        inouts = [1l];
        operation = Load_integer {value = 20L};
    };
    {
        inouts = [1l; 0l; 2l];
        operation = Create_array;
    };
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "create_array" correct prog 