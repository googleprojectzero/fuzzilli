open Program_types

let input = 
"let v0 = 10;
let v4 = 13;
const v2 = [12];
with (v2) {
    const v3 = 0.0;
    const v9 = v0 - v4;
}"

let correct = [
    {
        inouts = [0l];
        operation = Load_integer {value = 10L};
    };
    {
        inouts = [1l];
        operation = Load_integer {value = 13L};
    };
    {
        inouts = [2l];
        operation = Load_integer {value = 12L};
    };
    {
        inouts = [2l; 3l];
        operation = Create_array;
    };
    {
        inouts = [3l];
        operation = Begin_with;
    };
    {
        inouts = [4l];
        operation = Load_float {value = 0.0};
    };
    {
        inouts = [0l; 1l; 5l];
        operation = Binary_operation {op = Sub};
    };
    {
        inouts = [];
        operation = End_with;
    }
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false in
    Alcotest.(check (list Util.inst_testable)) "with" correct prog 