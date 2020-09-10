open Program_types

let input = 
"if(1){
    const v0 = 3;
} else if(2){
    const v1 = 4;
} else {
    const v2 = 5;
}
"

let correct = [
    {
        inouts = [0l];
        operation = Load_integer {value = 1L};
    };
    {
        inouts = [0l];
        operation = Begin_if;
    };
    {
        inouts = [1l];
        operation = Load_integer {value = 3L};
    };
    {
        inouts = [];
        operation = Begin_else;
    };
    {
        inouts = [2l];
        operation = Load_integer {value = 2L};
    };
    {
        inouts = [2l];
        operation = Begin_if;
    };
    {
        inouts = [3l];
        operation = Load_integer {value = 4L};
    };
    {
        inouts = [];
        operation = Begin_else;
    };
    {
        inouts = [4l];
        operation = Load_integer {value = 5L};
    };
    {
        inouts = [];
        operation = End_if;
    };
    {
        inouts = [];
        operation = End_if;
    };
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false in
    Alcotest.(check (list Util.inst_testable)) "if_else" correct prog
    