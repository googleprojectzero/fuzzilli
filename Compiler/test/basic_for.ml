open Program_types

let input = 
"for(let v0 = 2; v0 < 10; v0 = v0 + 1){
    let v2 = v0 + 12;
}"

let correct = [
    {
        inouts = [0l];
        operation = Load_integer {value = 2L};
    };
    {
        inouts = [1l];
        operation = Load_integer {value = 10L};
    };
    {
        inouts = [0l; 1l; 2l];
        operation = Compare {op = Less_than};
    };
    {
        inouts = [3l];
        operation = Load_integer {value = 0L};
    };
    {
        inouts = [2l; 3l];
        operation = Begin_while {comparator = Not_equal};
    };
    {
        inouts = [4l];
        operation = Load_integer {value = 12L};
    };
    {
        inouts = [0l; 4l; 5l];
        operation = Binary_operation {op = Add};

    };
    {
        inouts = [6l];
        operation = Load_integer {value = 1L};
    };
    {
        inouts = [0l; 6l; 7l];
        operation = Binary_operation {op = Add};
    };
    {
        inouts = [0l; 7l];
        operation = Reassign;
    };
    {
        inouts = [8l];
        operation = Load_integer {value = 10L;}
    };
    {
        inouts = [0l; 8l; 9l];
        operation = Compare {op = Less_than};
    };
    {
        inouts = [2l; 9l];
        operation = Reassign;
    };
    {
        inouts = [];
        operation = End_while;
    }
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false in
    Alcotest.(check (list Util.inst_testable)) "basic_for" correct prog
    