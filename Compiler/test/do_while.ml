open Program_types

let input = 
"let v0 = 0;
do{
    v0 = v0 + 1;
}while(v0 < 10);
"

let correct = [
    {
        inouts = [0l];
        operation = Load_integer {value = 0L};
    };
    {
        inouts = [1l];
        operation = Load_integer {value = 0L};
    };
    {
        inouts = [1l; 2l];
        operation = Dup;
    };
    {
        inouts = [2l; 1l];
        operation = Begin_do_while {comparator = Not_equal};
    };
    {
        inouts = [3l];
        operation = Load_integer {value = 1L};
    };
    {
        inouts = [0l; 3l; 4l];
        operation = Binary_operation {op = Add};
    };
    {
        inouts = [0l; 4l];
        operation = Reassign;
    };
    {
        inouts = [5l];
        operation = Load_integer {value = 10L};
    };
    {
        inouts = [0l; 5l; 6l];
        operation = Compare {op = Less_than};
    };
    {
        inouts = [2l; 6l];
        operation = Reassign;
    };
    {
        inouts = [];
        operation = End_do_while;
    }
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false in
    Alcotest.(check (list Util.inst_testable)) "do_while" correct prog 