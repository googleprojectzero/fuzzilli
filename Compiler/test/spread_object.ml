open Program_types

let input = 
"let v0 = 1;
const v1 = 2
const v7 = {toString:1+2,e:v0+v1};
const v11 = {foobar:3+4,...v7};"

let correct = [
    {
        inouts = [0l];
        operation = Load_integer {value = 1L};
    };
    {
        inouts = [1l];
        operation = Load_integer {value = 2L};
    };
    {
        inouts = [2l];
        operation = Load_integer {value = 1L};
    };
    {
        inouts = [3l];
        operation = Load_integer {value = 2L};
    };
    {
        inouts = [2l; 3l; 4l];
        operation = Binary_operation {op = Add};
    };
    {
        inouts = [0l; 1l; 5l];
        operation = Binary_operation {op = Add};
    };
    {
        inouts = [4l; 5l; 6l];
        operation = Create_object {property_names = ["toString"; "e"]};
    };
    {
        inouts = [7l];
        operation = Load_integer {value = 3L};
    };
    {
        inouts = [8l];
        operation = Load_integer {value = 4L};
    };
    {
        inouts = [7l; 8l; 9l];
        operation = Binary_operation {op = Add};
    };
    {
        inouts = [9l; 6l; 10l];
        operation = Create_object_with_spread {property_names = ["foobar"]}
    }
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false in
    Alcotest.(check (list Util.inst_testable)) "spread_object" correct prog 