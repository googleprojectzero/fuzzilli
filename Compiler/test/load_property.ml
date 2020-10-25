open Program_types

let input = 
"const v0 = {};
const v1 = 13.37;
const v2 = v0.__proto__;"

let correct = [
    {
        inouts = [0l;];
        operation = Create_object {property_names = []};
    };
    {
        inouts = [1l];
        operation = Load_float {value = 13.37};
    };
    {
        inouts = [0l; 2l];
        operation = Load_property {property_name = "__proto__"};
    }
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "load_property" correct prog 