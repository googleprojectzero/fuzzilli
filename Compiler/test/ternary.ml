open Program_types

let input = 
"var a = 1 < 0 ? 2 : 3;"

let correct = [
    {
        inouts = [0l];
        operation = Load_integer {value = 0L};
    }; 
    {
        inouts = [1l];
        operation = Load_integer {value = 1L};
    };
    {
        inouts = [2l];
        operation = Load_integer{value = 0L}
    };
    {
        inouts = [1l; 2l; 3l];
        operation = Compare {op = Less_than; };
    };
    {
        inouts = [3l];
        operation = Begin_if;
    };
    {
        inouts = [4l];
        operation = Load_integer {value = 2L};
    };
    {
        inouts = [0l; 4l];
        operation = Reassign;
    };
    {
        inouts = [];
        operation = Begin_else;
    };
    {
        inouts = [5l];
        operation = Load_integer {value = 3L};
    };
    {
        inouts = [0l; 5l];
        operation = Reassign;
    };
    {
        inouts = [];
        operation = End_if;
    }
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false in
    Alcotest.(check (list Util.inst_testable)) "ternary_test" correct prog 