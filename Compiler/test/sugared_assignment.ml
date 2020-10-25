open Program_types

let input = 
"let v0 = 1;
v0 += 10;
let v1 = 2;
v1 -= 20;"

let correct = [
    {
        inouts = [0l];
        operation = Load_integer {value = 1L};
    };
    {
        inouts = [1l];
        operation = Load_integer {value = 10L};
    };
    {
        inouts = [0l; 1l; 2l];
        operation = Binary_operation {op = Add};
    };
    {
        inouts = [0l; 2l];
        operation = Reassign;
    };
    {
        inouts = [3l];
        operation = Load_integer {value = 2L};
    };
    {
        inouts = [4l];
        operation = Load_integer {value = 20L};
    };
    {
        inouts = [3l; 4l; 5l];
        operation = Binary_operation {op = Sub};
    };
    {
        inouts = [3l; 5l];
        operation = Reassign;
    }
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false in
    Alcotest.(check (list Util.inst_testable)) "sugared_assignment" correct prog 