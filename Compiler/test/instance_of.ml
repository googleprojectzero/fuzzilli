open Program_types

let input = 
"const v0 = 1;
const v1 = 2;
const v2 = v1 instanceof v0;
"

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
        inouts = [1l; 0l; 2l];
        operation = Instance_of;
    };
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false in
    Alcotest.(check (list Util.inst_testable)) "instance_of" correct prog
    