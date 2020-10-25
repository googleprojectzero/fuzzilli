open Program_types

let input = 
"const v3 = [0,1,2];
const v5 = v3[0];
const v7 = v3[v5];"

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
        operation = Load_integer {value = 2L};
    };
    {
        inouts = [0l; 1l; 2l; 3l];
        operation = Create_array;
    };
    {
        inouts = [3l; 4l];
        operation = Load_element {index = 0L};
    };
    {
        inouts = [3l; 4l; 5l];
        operation = Load_computed_property;
    }
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "load_array_index" correct prog 