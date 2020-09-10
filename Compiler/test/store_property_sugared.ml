open Program_types

let input = 
"const v0 = {};
const v1 = 13.37;
v0.a = 10;
v0.a += v1;"

let correct = [
    {
        inouts = [0l];
        operation = Create_object {property_names = []};
    };
    {
        inouts = [1l];
        operation = Load_float {value = 13.37};
    };
    {
        inouts = [2l];
        operation = Load_integer {value = 10L};
    };
    {
        inouts = [0l; 2l];
        operation = Store_property {property_name = "a"};
    };
    {
        inouts = [0l; 3l];
        operation = Load_property {property_name = "a"};
    };
    {
        inouts = [3l; 1l; 4l];
        operation = Binary_operation {op = Add};
    };
    {
        inouts = [0l; 4l];
        operation = Store_property {property_name = "a"};
    }
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false in
    Alcotest.(check (list Util.inst_testable)) "store_property_sugared" correct prog 