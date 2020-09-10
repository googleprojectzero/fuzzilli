open Program_types

let input = 
"const v0 = 4294967296;
const v1 = isNaN;
const v2 = v0 === v1;
const v3 = v1 == v1;
const v4 = 13.37;
const v5 = [v4,v4];
const v6 = 1337;
const v7 = {toString:v5,e:v6};"

let correct = [
    {
        inouts = [0l];
        operation = Load_integer {value = 4294967296L};
    };
    {
        inouts = [1l];
        operation = Load_builtin {builtin_name = "isNaN"};
    };
    {
        inouts = [0l; 1l; 2l];
        operation = Compare {op = Strict_equal};
    };
    {
        inouts = [1l; 1l; 3l];
        operation = Compare {op = Equal};
    };
    {
        inouts = [4l];
        operation = Load_float {value = 13.37};
    };
    {
        inouts = [4l; 4l; 5l];
        operation = Create_array;
    };
    {
        inouts = [6l];
        operation = Load_integer {value = 1337L};
    };
    {
        inouts = [5l; 6l; 7l];
        operation = Create_object {property_names = ["toString"; "e"]};
    }
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false in
    Alcotest.(check (list Util.inst_testable)) "prog_10" correct prog 