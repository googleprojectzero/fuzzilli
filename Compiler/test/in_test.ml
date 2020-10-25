open Program_types

let input = 
"const v0 = 10;
const v3 = [15,20];
const v4 = v0 in v3;
"

let correct = [
    {
        inouts = [0l];
        operation = Load_integer {value = 10L};
    };
    {
        inouts = [1l];
        operation = Load_integer {value = 15L};
    };
    {
        inouts = [2l];
        operation = Load_integer {value = 20L};
    };
    {
        inouts = [1l; 2l; 3l];
        operation = Create_array;
    };
    {
        inouts = [0l; 3l; 4l];
        operation = In;
    };

]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "in_test" correct prog
    