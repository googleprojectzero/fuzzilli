open Program_types

let input = 
"let v0 = 0;
v0 = 12;"

let correct = [
    {
        inouts = [0l];
        operation = Load_integer {value = 0L};
    };
    {
        inouts = [1l];
        operation = Load_integer {value = 12L};
    };
    {
        inouts = [0l; 1l];
        operation = Reassign;
    };
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false in
    Alcotest.(check (list Util.inst_testable)) "single_let" correct prog 