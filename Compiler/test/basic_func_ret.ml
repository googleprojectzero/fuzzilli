open Program_types

let input = 
"function v1(v2,v3) {
    let v4 = v2 * v3;
    return v4;
}
"

let correct = [
    {
        inouts = [0l; 1l; 2l];
        operation = Begin_plain_function_definition {
            signature = Some {
                input_types = [Util.default_input_type; Util.default_input_type];
                output_type = Some Util.default_output_type;
            };
        };
    };
    {
        inouts = [1l; 2l; 3l];
        operation = Binary_operation {op = Mul};
    };
    {
        inouts = [3l];
        operation = Return;
    };
    {
        inouts = [];
        operation = End_plain_function_definition;
    }
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "basic_func_ret" correct prog 