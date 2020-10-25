open Program_types

let input = 
"const v0 = 1337;
const v1 = [v0];
const v2 = [v1,v1];
const v3 = 13.37;
const v4 = 1337;
delete v3[v2];
const v10 = \"function\";
delete v10.length;
"

let correct = [
    {
        inouts = [0l];
        operation = Load_integer {value = 1337L};
    };
    {
        inouts = [0l; 1l];
        operation = Create_array;
    };
    {
        inouts = [1l; 1l; 2l];
        operation = Create_array;
    };
    {
        inouts = [3l];
        operation = Load_float {value = 13.37};
    };
    {
        inouts = [4l];
        operation = Load_integer {value = 1337L};
    };
    {
        inouts = [3l; 2l];
        operation = Delete_computed_property;
    };
    {
        inouts = [5l];
        operation = Load_string {value = "function"};
    };
    {
        inouts = [5l];
        operation = Delete_property {property_name = "length"};
    }
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "del_test" correct prog 