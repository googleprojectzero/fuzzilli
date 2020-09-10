open Program_types

let input = 
"const v0 = 1 == 1;
const v1 = 1 === 1;
const v2 = 2 >= 2;
const v3 = 7 < 9;"

let correct = [
    {
        inouts = [0l];
        operation = Load_integer {value = 1L};
    };
    {
        inouts = [1l];
        operation = Load_integer {value = 1L};
    };
    {
        inouts = [0l; 1l; 2l];
        operation = Compare {op = Equal};
    };
    {
        inouts = [3l];
        operation = Load_integer {value = 1L};
    };
    {
        inouts = [4l];
        operation = Load_integer {value = 1L};
    };
    {
        inouts = [3l; 4l; 5l];
        operation = Compare {op = Strict_equal};
    };
    {
        inouts = [6l];
        operation = Load_integer {value = 2L};
    };
    {
        inouts = [7l];
        operation = Load_integer {value = 2L};
    };
    {
        inouts = [6l; 7l; 8l];
        operation = Compare {op = Greater_than_or_equal};
    };
    {
        inouts = [9l];
        operation = Load_integer {value = 7L};
    };
    {
        inouts = [10l];
        operation = Load_integer {value = 9L};
    };
    {
        inouts = [9l; 10l; 11l];
        operation = Compare {op = Less_than};
    };
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false in
    Alcotest.(check (list Util.inst_testable)) "basic_compare_test" correct prog 