open Program_types

let input = 
"var a = function () {};
function b() {__f_1653();}
b();
function __f_1653(__v_9774, __v_9775) {
  return 7;
}
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
        inouts = [];
        operation = End_plain_function_definition;
    };
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
        inouts = [1l; 4l];
        operation = Call_function;
    };
    {
        inouts = [5l; 6l; 7l];
        operation = Begin_plain_function_definition {
            signature = Some {
                input_types = [Util.default_input_type; Util.default_input_type];
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
    let prog = Compiler.flow_ast_to_inst_list ast false false in
    Alcotest.(check (list Util.inst_testable)) "func_dec_order" correct prog 