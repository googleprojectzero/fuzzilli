open Program_types

let input = 
"const v0 = function () { const v1 = 12; return v1;}
const v2 = v0();
"

let correct = [
    {
        inouts = [0l];
        operation = Begin_plain_function_definition {
            signature = Some {
                input_types = [];
                output_type = Some Util.default_output_type;
            };
        };
    };
    {
        inouts = [1l];
        operation = Load_integer {value = 12L}
    };
    {
        inouts = [1l];
        operation = Return;
    };
    {
        inouts = [];
        operation = End_plain_function_definition;
    };
    {
        inouts = [0l; 2l];
        operation = Call_function;
    };
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false in
    Alcotest.(check (list Util.inst_testable)) "func_exp_test" correct prog 