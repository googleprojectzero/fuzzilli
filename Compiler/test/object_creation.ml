open Program_types

let input = 
"let v0 = 1;
const v1 = 2
const v7 = {toString:1+2,e:v0+v1};"

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
        operation = Create_object {property_names = ["toString"; "e"]}
    }

]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "object_creation" correct prog 