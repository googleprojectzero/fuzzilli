open Program_types

let input = 
"const v0 = 12;
const v1 = [v0,v0,v0];
const v2 = 10;
v1[v2 + 20] += 30;"

let correct = [
    {
        inouts = [0l];
        operation = Load_integer {value = 12L};
    };
    {
        inouts = [0l; 0l; 0l; 1l];
        operation = Create_array;
    };
    {
        inouts = [2l];
        operation = Load_integer {value = 10L};
    };
    {
        inouts = [3l];
        operation = Load_integer {value = 20L};
    };
    {
        inouts = [2l; 3l; 4l];
        operation = Binary_operation {op = Add};
    };
    {
        inouts = [5l];
        operation = Load_integer {value = 30L};
    };
    {
        inouts = [1l; 4l; 6l];
        operation = Load_computed_property;
    };
    {
        inouts = [6l; 5l; 7l];
        operation = Binary_operation {op = Add};
    };
    {
        inouts = [1l; 4l; 7l];
        operation = Store_computed_property
    };

]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false in
    Alcotest.(check (list Util.inst_testable)) "array_assign_sugared" correct prog 