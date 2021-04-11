open Program_types

let input = 
"function b() {a();}
function a() {
  return 7;
}
"

let correct = [
    {
        inouts = [1l];
        operation = Begin_plain_function_definition {
            signature = Some {
                input_types = [];
                output_type = Some Util.default_output_type;
            };
        };
    };
    {
        inouts = [2l];
        operation = Load_from_scope {id = "v5"};
    };
    {
        inouts = [2l; 3l];
        operation = Call_function;
    };
    {
        inouts = [];
        operation = End_plain_function_definition;
    };
    {
        inouts = [5l; 6l; 7l];
        operation = Begin_plain_function_definition {
            signature = Some {
                input_types = [];
                output_type = Some Util.default_output_type;
            };
        };
    };
    {
        inouts = [8l];
        operation = Load_integer {value = 7L};
    };
    {
        inouts = [8l];
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
    Alcotest.(check (list Util.inst_testable)) "func_dec_order" correct prog 