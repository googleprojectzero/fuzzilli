open Program_types

let input = 
"var a = [1,,1];"

let correct = [
    {
        inouts = [0l];
        operation = Load_integer {value = 1L};
    };
    {
        inouts = [1l];
        operation = Load_undefined;
    };
    {
        inouts = [2l];
        operation = Load_integer {value = 1L};
    };
    {
        inouts = [0l; 1l; 2l; 3l];
        operation = Create_array;
    };
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false in
    Alcotest.(check (list Util.inst_testable)) "array_hole" correct prog 