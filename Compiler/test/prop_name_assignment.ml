open Program_types

let input = 
"const v0 = \"function\";
const v1 = 13.37;
const v2 = v0.__proto__;
v2.toString = v1;"

let correct = [
    {
        inouts = [0l];
        operation = Load_string {value = "function"};
    };
    {
        inouts = [1l];
        operation = Load_float {value = 13.37};
    };
    {
        inouts = [0l; 2l];
        operation = Load_property {property_name = "__proto__"};
    };
    {
        inouts = [2l; 1l];
        operation = Store_property {property_name = "toString"};
    }
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false in
    Alcotest.(check (list Util.inst_testable)) "prop_name_assignment" correct prog 