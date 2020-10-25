open Program_types

let input = 
"function test(a) {
  a[0] = 1.5;
}
a = new Array();"

let correct = [
    {
        inouts = [0l; 1l];
        operation = Begin_plain_function_definition {
            signature = Some {
                input_types = [Util.default_input_type];
                output_type = Some Util.default_output_type;
            };
        };
    };
    {
        inouts = [2l];
        operation = Load_integer {value = 0L};
    };
    {
        inouts = [3l];
        operation = Load_float {value = 1.5};
    };
    {
        inouts = [1l; 2l; 3l];
        operation = Store_computed_property;
    };
    {
        inouts = [];
        operation = End_plain_function_definition;
    };
    {
        inouts = [4l];
        operation = Load_builtin {builtin_name = "Array"};
    };
    {
        inouts = [4l; 5l];
        operation = Construct;
    };
    {
        inouts = [5l; 6l];
        operation = Dup;
    };
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "func_param_scoping" correct prog 